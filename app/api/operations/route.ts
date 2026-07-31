import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRpc, stagingRest } from "@/lib/hq-server";

export const dynamic = "force-dynamic";
type Module = "marketing" | "support" | "field";
type Row = Record<string, unknown>;
const mediaKeys = ["photo_url", "image_url", "document_url", "file_url", "selfie_url", "bi_url", "nuit_url", "proof_url", "document_front_path", "document_back_path", "selfie_path", "photos", "documents", "files", "attachments"];
const mediaFromRow = (row: Row) => mediaKeys.flatMap((key) => {
  const value = row[key];
  if (typeof value === "string" && value.trim()) return [{ key, url: value.trim(), label: key.replaceAll("_", " ") }];
  if (Array.isArray(value)) return value.flatMap((item) => typeof item === "string" && item.trim() ? [{ key, url: item.trim(), label: key.replaceAll("_", " ") }] : item && typeof item === "object" && typeof (item as Row).url === "string" ? [{ key, url: String((item as Row).url), label: String((item as Row).label || key).replaceAll("_", " ") }] : []);
  return [];
});
const withKycMedia = (row: Row) => ({ ...row, _kyc_media: mediaFromRow(row) });
const access: Record<Module, string[]> = {
  marketing: ["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS", "MARKETING"],
  support: ["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS", "CUSTOMER_SUPPORT"],
  field: ["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS", "FIELD"],
};
const getRows = async (path: string) => { try { return await stagingRest(path) as Row[]; } catch (error) { console.error("HQ operational source unavailable", path, error); return []; } };

export async function GET(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401 });
  const module = request.nextUrl.searchParams.get("module") as Module;
  if (!access[module]?.includes(actor.role)) return NextResponse.json({ error: "Sem permissão para este módulo." }, { status: 403 });
  let collections: Record<string, Row[]>;
  if (module === "support") {
    const [tickets, messages, disputes] = await Promise.all([getRows("support_tickets?select=*&order=updated_at.desc&limit=120"), getRows("support_messages?select=*&order=created_at.desc&limit=160"), getRows("order_disputes?select=*&order=created_at.desc&limit=80")]);
    collections = { tickets, messages, disputes };
  } else if (module === "marketing") {
    const [requests, campaigns, events] = await Promise.all([getRows("marketing_requests?select=*&order=created_at.desc&limit=150"), getRows("marketing_campaigns?select=*&order=created_at.desc&limit=120"), getRows("marketing_events?select=*&order=created_at.desc&limit=120")]);
    collections = { requests, campaigns, events };
  } else {
    const [deligoKyc, sarcaDrivers, comunhaoChurches, taomozSellerKyc, taomozSellers, restaurants, couriers, notes] = await Promise.all([
      getRows("profiles?select=id,full_name,phone,role,city,address,email,kyc_status,kyc_rejection_reason,approval_submitted_at,approval_sla_deadline,verification_score,is_blocked,created_at,updated_at&role=in.(restaurant,courier)&order=updated_at.desc&limit=250"),
      getRows("driver_profiles?select=*&order=updated_at.desc&limit=250"),
      getRows("church_applications?select=*&order=updated_at.desc&limit=250"),
      getRows("kyc_submissions?select=*&role=eq.seller&order=updated_at.desc&limit=250"),
      getRows("seller_profiles?select=*&order=updated_at.desc&limit=250"),
      getRows("restaurants?select=*&order=created_at.desc&limit=120"), getRows("couriers?select=*&order=created_at.desc&limit=120"), getRows("field_internal_notes?select=*&order=created_at.desc&limit=100"),
    ]);
    const tag = (rows: Row[], platform: string, subjectType: string) => rows.map(row => withKycMedia({ ...row, _platform: platform, _subject_type: subjectType }));
    const sellerByProfile = new Map(taomozSellers.map(row => [String(row.profile_id || ""), row]));
    const taomozKyc = taomozSellerKyc.map(row => ({ ...sellerByProfile.get(String(row.profile_id || "")), ...row }));
    collections = {
      verifications: [...tag(deligoKyc, "DeliGo", "Estafeta / Restaurante"), ...tag(sarcaDrivers, "SARCA", "Condutor"), ...tag(comunhaoChurches, "Comunhão", "Igreja"), ...tag(taomozKyc, "TaoMoz", "Vendedor")],
      deligoKyc: tag(deligoKyc, "DeliGo", "Estafeta / Restaurante"), sarcaDrivers: tag(sarcaDrivers, "SARCA", "Condutor"), comunhaoChurches: tag(comunhaoChurches, "Comunhão", "Igreja"), taomozSellers: tag(taomozKyc, "TaoMoz", "Vendedor"), restaurants, couriers, notes,
    };
  }
  return NextResponse.json({ module, collections, checkedAt: new Date().toISOString(), permissions: { canDecideKyc: ["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS"].includes(actor.role) } }, { headers: { "Cache-Control": "private, no-store" } });
}

export async function PATCH(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401 });
  const body = await request.json() as { module?: Module; entity?: string; id?: string; action?: string; platform?: string; reason?: string };
  if (!body.module || !access[body.module]?.includes(actor.role)) return NextResponse.json({ error: "Sem permissão." }, { status: 403 });
  if (!body.id) return NextResponse.json({ error: "Registo inválido." }, { status: 400 });
  if (body.module === "support" && body.entity === "tickets" && ["open", "in_progress", "resolved", "closed"].includes(body.action || "")) {
    const resolved = ["resolved", "closed"].includes(body.action || "");
    const now = new Date().toISOString();
    const update = { status: body.action, updated_at: now, ...(resolved ? { resolved_at: now, resolution: "Concluído no HQ corporativo" } : {}) };
    const rows = await stagingRest(`support_tickets?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify(update) });
    return NextResponse.json({ ok: true, rows });
  }
  if (body.module === "field" && body.entity === "kyc" && ["approve", "reject", "correction"].includes(body.action || "")) {
    if (!["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS"].includes(actor.role)) return NextResponse.json({ error: "Field verifica; a decisão exige Operações ou Supervisor." }, { status: 403 });
    if (["reject", "correction"].includes(body.action || "") && (body.reason || "").trim().length < 6) return NextResponse.json({ error: "Indique um motivo com pelo menos 6 caracteres." }, { status: 400 });
    const now = new Date().toISOString(), platform = body.platform || "";
    if (platform === "DeliGo") {
      const kyc_status = body.action === "approve" ? "approved" : body.action === "reject" ? "rejected" : "pending";
      await stagingRest(`profiles?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify({ kyc_status, kyc_rejection_reason: body.action === "approve" ? null : body.reason || null, updated_at: now }) });
    } else if (platform === "SARCA") {
      const status = body.action === "approve" ? "active" : body.action === "reject" ? "rejected" : "pending";
      await stagingRest(`driver_profiles?user_id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify({ status, onboarding_reviewed_at: now, rejection_reason: body.action === "approve" ? null : body.reason || null, is_online: false, ...(body.action === "approve" ? { onboarding_completed: true } : {}) }) });
      await stagingRest(`driver_documents?driver_user_id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify({ status: body.action === "approve" ? "approved" : body.action === "reject" ? "rejected" : "pending", rejection_reason: body.action === "approve" ? null : body.reason || null, reviewed_at: now }) });
    } else if (platform === "TaoMoz") {
      const status = body.action === "approve" ? "approved" : body.action === "reject" ? "rejected" : "pending";
      const submissions = await stagingRest(`kyc_submissions?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify({ status, rejection_reason: body.action === "approve" ? null : body.reason || null, reviewed_at: now }) }) as Row[];
      const profileId = String(submissions?.[0]?.profile_id || "");
      if (profileId) await stagingRest(`seller_profiles?profile_id=eq.${encodeURIComponent(profileId)}`, { method: "PATCH", body: JSON.stringify({ kyc_status: status, is_active: body.action === "approve", updated_at: now }) });
    } else if (platform === "Comunhão") {
      if (body.action === "approve") return NextResponse.json({ error: "A aprovação exige criação da igreja, código e trial pelo adaptador nativo." }, { status: 409 });
      await stagingRest(`church_applications?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify({ status: body.action === "reject" ? "rejected" : "changes_requested", review_notes: body.reason || null, reviewed_at: now }) });
    } else return NextResponse.json({ error: "Plataforma KYC inválida." }, { status: 400 });
    await hqRpc("hq_log_platform_action_v1", { p_actor_auth_user_id: actor.authUserId, p_platform: platform, p_action: `KYC_${body.action}`, p_target_type: "kyc", p_target_id: body.id, p_metadata: { reason: body.reason || null } });
    return NextResponse.json({ ok: true });
  }
  return NextResponse.json({ error: "Acção ainda não autorizada neste fluxo." }, { status: 400 });
}

export async function POST(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401 });
  const body = await request.json() as { module?: Module; entity?: string; id?: string; text?: string; title?: string };
  if (!body.module || !access[body.module]?.includes(actor.role)) return NextResponse.json({ error: "Sem permissão." }, { status: 403 });
  if (body.module === "support" && body.entity === "message" && body.id && (body.text || "").trim().length >= 2) {
    const rows = await stagingRest("support_messages", { method: "POST", body: JSON.stringify({ ticket_id: body.id, sender_id: actor.authUserId, sender_name: actor.name, sender_role: actor.role, text: body.text?.trim() }) });
    await stagingRest(`support_tickets?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify({ status: "in_progress", updated_at: new Date().toISOString(), reason: body.text?.trim() }) });
    return NextResponse.json({ ok: true, rows });
  }
  if (body.module === "field" && body.entity === "note" && body.id && (body.text || "").trim().length >= 3) {
    const rows = await stagingRest("field_internal_notes", { method: "POST", body: JSON.stringify({ entity_id: body.id, entity_type: "kyc", note: body.text?.trim(), created_by: actor.authUserId }) });
    return NextResponse.json({ ok: true, rows });
  }
  if (body.module === "marketing" && body.entity === "campaign" && (body.title || "").trim().length >= 3) {
    const rows = await stagingRest("marketing_campaigns", { method: "POST", body: JSON.stringify({ created_by: actor.authUserId, title: body.title?.trim(), placement: "home", campaign_type: "institutional", type: "institutional", objective: "awareness", target_type: "none", starts_at: new Date().toISOString(), action_label: "Ver agora", priority: 0, budget: 0, status: "draft", active: false, metadata: { source: "hq" } }) });
    return NextResponse.json({ ok: true, rows });
  }
  return NextResponse.json({ error: "Dados insuficientes para criar o registo." }, { status: 400 });
}
