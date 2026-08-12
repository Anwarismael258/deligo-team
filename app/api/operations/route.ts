import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRpc, stagingRest } from "@/lib/hq-server";
import { buildPlatformDecision, type PlatformDecision } from "@/lib/platform-decisions";
import { platformFunction, platformRest, platformRpc, type PlatformBackend } from "@/lib/platform-backends";

export const dynamic = "force-dynamic";

type Module = "marketing" | "support" | "field";
type Row = Record<string, unknown>;

const access: Record<Module, string[]> = {
  marketing: ["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS", "MARKETING"],
  support: ["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS", "CUSTOMER_SUPPORT"],
  field: ["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS", "FIELD"],
};

const mediaKeys = ["photo_url", "image_url", "document_url", "file_url", "selfie_url", "bi_url", "nuit_url", "proof_url", "document_front_path", "document_back_path", "selfie_path", "photos", "documents", "files", "attachments"];
const getRows = async (path: string) => {
  try { return await stagingRest(path) as Row[]; }
  catch { return []; }
};
const withKycMedia = (row: Row) => ({
  ...row,
  _kyc_media: mediaKeys.flatMap((key) => {
    const value = row[key];
    if (typeof value === "string" && value.trim()) return [{ key, url: value.trim(), label: key.replaceAll("_", " ") }];
    if (Array.isArray(value)) return value.flatMap((item) => typeof item === "string" && item.trim() ? [{ key, url: item.trim(), label: key.replaceAll("_", " ") }] : []);
    return [];
  }),
});

export async function GET(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401 });
  const requestedModule = request.nextUrl.searchParams.get("module") as Module;
  if (!access[requestedModule]?.includes(actor.role)) return NextResponse.json({ error: "Sem permissão para este módulo." }, { status: 403 });

  let collections: Record<string, Row[]>;
  if (requestedModule === "support") {
    const [tickets, messages, disputes] = await Promise.all([
      getRows("support_tickets?select=*&order=updated_at.desc&limit=120"),
      getRows("support_messages?select=*&order=created_at.asc&limit=300"),
      getRows("order_disputes?select=*&order=updated_at.desc&limit=80"),
    ]);
    collections = { tickets, messages, disputes };
  } else if (requestedModule === "marketing") {
    const [requests, campaigns, events] = await Promise.all([
      getRows("marketing_requests?select=*&order=created_at.desc&limit=150"),
      getRows("marketing_campaigns?select=*&order=created_at.desc&limit=120"),
      getRows("marketing_events?select=*&order=created_at.desc&limit=120"),
    ]);
    collections = { requests, campaigns, events };
  } else {
    const [deligoKyc, sarcaDrivers, comunhaoChurches, taomozSellerKyc, taomozSellers, mestre24Kyc, mestre24Profiles, restaurants, couriers, notes] = await Promise.all([
      getRows("profiles?select=id,full_name,phone,role,city,address,email,kyc_status,kyc_rejection_reason,approval_submitted_at,approval_sla_deadline,verification_score,is_blocked,created_at,updated_at&role=in.(restaurant,courier)&order=updated_at.desc&limit=250"),
      getRows("driver_profiles?select=*&order=updated_at.desc&limit=250"),
      getRows("church_applications?select=*&order=updated_at.desc&limit=250"),
      getRows("kyc_submissions?select=*&role=eq.seller&order=updated_at.desc&limit=250"),
      getRows("seller_profiles?select=*&order=updated_at.desc&limit=250"),
      platformRest("mestre24", "kyc_verifications?select=*&order=created_at.desc&limit=250").catch(() => []) as Promise<Row[]>,
      platformRest("mestre24", "professional_profiles?select=user_id,headline,verification_status,subscription_status,visible_in_marketplace,created_at,updated_at&order=updated_at.desc&limit=250").catch(() => []) as Promise<Row[]>,
      getRows("restaurants?select=*&order=created_at.desc&limit=120"),
      getRows("couriers?select=*&order=created_at.desc&limit=120"),
      getRows("field_internal_notes?select=*&order=created_at.desc&limit=100"),
    ]);
    const tag = (rows: Row[], platform: string, subjectType: string) => rows.map((row) => withKycMedia({ ...row, _platform: platform, _subject_type: subjectType }));
    const sellerByProfile = new Map(taomozSellers.map((row) => [String(row.profile_id || ""), row]));
    const taomozKyc = taomozSellerKyc.map((row) => ({ ...sellerByProfile.get(String(row.profile_id || "")), ...row }));
    const mestre24ByUser = new Map(mestre24Profiles.map((row) => [String(row.user_id || ""), row]));
    const mestre24Verification = mestre24Kyc.map((row) => ({ ...mestre24ByUser.get(String(row.professional_user_id || "")), ...row }));
    collections = {
      verifications: [...tag(deligoKyc, "DeliGo", "Estafeta / Restaurante"), ...tag(sarcaDrivers, "SARCA", "Condutor"), ...tag(comunhaoChurches, "Comunhão", "Igreja"), ...tag(taomozKyc, "TaoMoz", "Vendedor")],
      deligoKyc: tag(deligoKyc, "DeliGo", "Estafeta / Restaurante"), sarcaDrivers: tag(sarcaDrivers, "SARCA", "Condutor"), comunhaoChurches: tag(comunhaoChurches, "Comunhão", "Igreja"), taomozSellers: tag(taomozKyc, "TaoMoz", "Vendedor"), restaurants, couriers, notes,
    };
    collections.mestre24Professionals = tag(mestre24Verification, "Mestre24", "Profissional");
    collections.verifications.push(...collections.mestre24Professionals);
  }
  return NextResponse.json({ module: requestedModule, collections, checkedAt: new Date().toISOString(), permissions: { canDecideKyc: ["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS"].includes(actor.role) } }, { headers: { "Cache-Control": "private, no-store" } });
}

export async function PATCH(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401 });
  const body = await request.json() as { module?: Module; entity?: string; id?: string; action?: string; platform?: string; reason?: string };
  if (!body.module || !access[body.module]?.includes(actor.role)) return NextResponse.json({ error: "Sem permissão." }, { status: 403 });
  if (!body.id) return NextResponse.json({ error: "Registo inválido." }, { status: 400 });

  if (body.module === "support" && body.entity === "tickets" && ["open", "in_progress", "resolved", "closed"].includes(body.action || "")) {
    const completed = ["resolved", "closed"].includes(body.action || "");
    await stagingRest(`support_tickets?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify({ status: body.action, updated_at: new Date().toISOString(), ...(completed ? { resolved_at: new Date().toISOString(), resolution: "Concluído no HQ corporativo" } : {}) }) });
    await hqRpc("hq_log_operational_action_v1", { p_actor_auth_user_id: actor.authUserId, p_module: "support", p_action: `SUPPORT_TICKET_${body.action}`, p_target_type: "support_ticket", p_target_id: body.id, p_metadata: {} });
    return NextResponse.json({ ok: true });
  }

  if (body.module === "marketing" && body.entity === "campaign" && ["draft", "published", "archived"].includes(body.action || "")) {
    await stagingRest(`marketing_campaigns?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify({ status: body.action, active: body.action === "published", updated_at: new Date().toISOString() }) });
    await hqRpc("hq_log_operational_action_v1", { p_actor_auth_user_id: actor.authUserId, p_module: "marketing", p_action: `MARKETING_CAMPAIGN_${body.action}`, p_target_type: "campaign", p_target_id: body.id, p_metadata: {} });
    return NextResponse.json({ ok: true });
  }

  if (body.module === "field" && body.entity === "kyc" && ["approve", "reject", "correction"].includes(body.action || "")) {
    if (!['SUPER_ADMIN', 'SUPERVISOR', 'OPERATIONS'].includes(actor.role)) return NextResponse.json({ error: "A decisão KYC exige Operações ou Supervisor." }, { status: 403 });
    if (["reject", "correction"].includes(body.action || "") && (body.reason || "").trim().length < 6) return NextResponse.json({ error: "Indique um motivo com pelo menos 6 caracteres." }, { status: 400 });
    const label = body.platform || "";
    const platform: PlatformBackend | null = label === "DeliGo" ? "deligo" : label === "SARCA" ? "sarca" : label === "TaoMoz" ? "taomoz" : label === "Mestre24" ? "mestre24" : label.includes("Comun") ? "comunhao" : null;
    if (!platform) return NextResponse.json({ error: "Plataforma KYC inválida." }, { status: 400 });
    const operation = buildPlatformDecision(platform, body.action as PlatformDecision, body.id, body.reason);
    if (operation.transport === "function") await platformFunction(platform, operation.name, operation.body);
    else if (operation.transport === "rpc") await platformRpc(platform, operation.name, operation.body);
    else await platformRest(platform, operation.name, { method: "PATCH", body: JSON.stringify({ ...operation.body, updated_at: new Date().toISOString() }) });
    await hqRpc("hq_log_platform_action_v1", { p_actor_auth_user_id: actor.authUserId, p_platform: platform, p_action: `KYC_${body.action}`, p_target_type: "kyc", p_target_id: body.id, p_metadata: { reason: body.reason || null } });
    return NextResponse.json({ ok: true });
  }
  return NextResponse.json({ error: "Ação ainda não autorizada neste fluxo." }, { status: 400 });
}

export async function POST(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401 });
  const body = await request.json() as { module?: Module; entity?: string; id?: string; text?: string; title?: string };
  if (!body.module || !access[body.module]?.includes(actor.role)) return NextResponse.json({ error: "Sem permissão." }, { status: 403 });

  if (body.module === "support" && body.entity === "message" && body.id && (body.text || "").trim().length >= 2) {
    const text = body.text?.trim() || "";
    await stagingRest("support_messages", { method: "POST", body: JSON.stringify({ ticket_id: body.id, sender_id: actor.authUserId, sender_name: actor.name, sender_role: actor.role, text }) });
    await stagingRest(`support_tickets?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify({ status: "in_progress", updated_at: new Date().toISOString() }) });
    await hqRpc("hq_log_operational_action_v1", { p_actor_auth_user_id: actor.authUserId, p_module: "support", p_action: "SUPPORT_MESSAGE_SENT", p_target_type: "support_ticket", p_target_id: body.id, p_metadata: { length: text.length } });
    return NextResponse.json({ ok: true }, { status: 201 });
  }
  if (body.module === "field" && body.entity === "note" && body.id && (body.text || "").trim().length >= 3) {
    const text = body.text?.trim() || "";
    await stagingRest("field_internal_notes", { method: "POST", body: JSON.stringify({ entity_id: body.id, entity_type: "kyc", note: text, created_by: actor.authUserId }) });
    await hqRpc("hq_log_operational_action_v1", { p_actor_auth_user_id: actor.authUserId, p_module: "field", p_action: "FIELD_NOTE_CREATED", p_target_type: "kyc", p_target_id: body.id, p_metadata: {} });
    return NextResponse.json({ ok: true }, { status: 201 });
  }
  if (body.module === "marketing" && body.entity === "campaign" && (body.title || "").trim().length >= 3) {
    const title = body.title?.trim() || "";
    const rows = await stagingRest("marketing_campaigns", { method: "POST", body: JSON.stringify({ created_by: actor.authUserId, title, placement: "home", campaign_type: "institutional", type: "institutional", objective: "awareness", target_type: "none", starts_at: new Date().toISOString(), action_label: "Ver agora", priority: 0, budget: 0, status: "draft", active: false, metadata: { source: "hq" } }) }) as Row[];
    const id = String(rows[0]?.id || "");
    await hqRpc("hq_log_operational_action_v1", { p_actor_auth_user_id: actor.authUserId, p_module: "marketing", p_action: "MARKETING_CAMPAIGN_CREATED", p_target_type: "campaign", p_target_id: id || title, p_metadata: {} });
    return NextResponse.json({ ok: true, rows }, { status: 201 });
  }
  return NextResponse.json({ error: "Dados insuficientes para criar o registo." }, { status: 400 });
}
