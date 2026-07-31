import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRpc } from "@/lib/hq-server";
import { platformFunction, platformRest, platformRpc, signPlatformPath, type PlatformBackend } from "@/lib/platform-backends";
import { buildPlatformDecision, type PlatformDecision } from "@/lib/platform-decisions";

export const dynamic = "force-dynamic";
const allowed = ["deligo", "comunhao", "sarca", "taomoz"] as const;
const isPlatform = (value: string): value is PlatformBackend => allowed.includes(value as PlatformBackend);
const safeRest = async (platform: PlatformBackend, path: string) => { try { return await platformRest(platform, path); } catch { return []; } };
const mediaFields = ["photo_url", "image_url", "document_url", "file_url", "selfie_url", "document_front_path", "document_back_path", "selfie_path", "proof_url", "photos", "documents", "files", "attachments"];
const signRecordMedia = async (platform: PlatformBackend, row: Record<string, unknown>) => { const copy = { ...row }; for (const field of mediaFields) { const value = copy[field]; if (typeof value === "string" && value) copy[field] = await signPlatformPath(platform, value); else if (Array.isArray(value)) copy[field] = await Promise.all(value.map(item => typeof item === "string" ? signPlatformPath(platform, item) : item)); } return copy; };
const signSnapshotMedia = async (platform: PlatformBackend, data: Record<string, unknown>) => { const result: Record<string, unknown> = { ...data }; for (const [key, value] of Object.entries(result)) if (Array.isArray(value)) result[key] = await Promise.all(value.map(item => item && typeof item === "object" ? signRecordMedia(platform, item as Record<string, unknown>) : item)); return result; };

export async function GET(request: NextRequest, context: { params: Promise<{ platform: string }> }) {
  const actor = await corporateActor();
  const { platform } = await context.params;
  if (!actor) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401 });
  if (!isPlatform(platform)) return NextResponse.json({ error: "Plataforma inválida." }, { status: 400 });
  if (!["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS"].includes(actor.role)) return NextResponse.json({ error: "Sem permissão para dados administrativos da plataforma." }, { status: 403 });
  try {
    const data = platform === "sarca"
      ? await platformFunction(platform, "admin-get-dashboard")
      : platform === "comunhao"
        ? { applications: await safeRest(platform, "church_applications?select=*&order=created_at.desc&limit=250"), subscriptions: await safeRest(platform, "church_subscriptions?select=*&order=created_at.desc&limit=100"), notifications: await safeRest(platform, "internal_notifications?select=*&order=created_at.desc&limit=100") }
        : platform === "taomoz"
          ? { users: await safeRest(platform, "profiles?select=id,full_name,phone,account_status,created_at&order=created_at.desc&limit=100"), kyc: await safeRest(platform, "kyc_submissions?select=*&status=eq.pending&order=created_at.desc&limit=100"), products: await safeRest(platform, "products?select=id,name,moderation_status,is_active,created_at&order=created_at.desc&limit=100"), orders: await safeRest(platform, "orders?select=id,order_number,status,payment_status,grand_total,created_at&order=created_at.desc&limit=100"), disputes: await safeRest(platform, "disputes?select=*&order=created_at.desc&limit=100"), withdrawals: await safeRest(platform, "money_operations?select=*&type=eq.withdrawal&order=created_at.desc&limit=100") }
          : { profiles: await safeRest(platform, "profiles?select=id,full_name,phone,role,kyc_status,is_blocked,created_at&order=created_at.desc&limit=250"), orders: await safeRest(platform, "orders?select=*&order=created_at.desc&limit=100"), restaurants: await safeRest(platform, "restaurants?select=*&order=created_at.desc&limit=100"), couriers: await safeRest(platform, "couriers?select=*&order=created_at.desc&limit=100"), support: await safeRest(platform, "support_tickets?select=*&order=updated_at.desc&limit=100"), marketing: await safeRest(platform, "marketing_campaigns?select=*&order=created_at.desc&limit=100"), disputes: await safeRest(platform, "order_disputes?select=*&order=created_at.desc&limit=100"), wallets: await safeRest(platform, "wallets?select=id,owner_id,balance,currency,created_at&order=created_at.desc&limit=100"), audit: await safeRest(platform, "admin_actions_log?select=*&order=created_at.desc&limit=100") };
    return NextResponse.json({ platform, data: await signSnapshotMedia(platform, data as Record<string, unknown>), checkedAt: new Date().toISOString() }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "Falha ao carregar a plataforma." }, { status: 502 }); }
}

export async function PATCH(request: NextRequest, context: { params: Promise<{ platform: string }> }) {
  const actor = await corporateActor();
  const { platform } = await context.params;
  if (!actor) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401 });
  if (!isPlatform(platform)) return NextResponse.json({ error: "Plataforma inválida." }, { status: 400 });
  if (!["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS"].includes(actor.role)) return NextResponse.json({ error: "A decisão exige Operações ou Supervisor." }, { status: 403 });
  const body = await request.json() as { action?: string; decision?: string; id?: string; reason?: string; payload?: Record<string, unknown> };
  if (!body.action || !body.id) return NextResponse.json({ error: "Acção e registo são obrigatórios." }, { status: 400 });
  const decision = body.decision || (body.action === "approve" ? "approve" : body.action === "reject" ? "reject" : body.action === "correction" ? "correction" : "");
  if (!["approve", "reject", "correction"].includes(decision)) return NextResponse.json({ error: "Decisão inválida." }, { status: 400 });
  if (["reject", "correction"].includes(decision) && !body.reason?.trim()) return NextResponse.json({ error: "Indique o motivo da rejeição ou correcção." }, { status: 400 });
  try {
    const expectedAction = platform === "comunhao" ? "review_application" : platform === "sarca" ? "review_driver" : platform === "taomoz" ? "review_kyc" : decision;
    if (body.action !== expectedAction) return NextResponse.json({ error: "Acção incompatível com a plataforma." }, { status: 400 });
    const operation = buildPlatformDecision(platform, decision as PlatformDecision, body.id, body.reason);
    const result = operation.transport === "function"
      ? await platformFunction(platform, operation.name, operation.body)
      : operation.transport === "rpc"
        ? await platformRpc(platform, operation.name, operation.body)
        : await platformRest(platform, operation.name, { method: "PATCH", body: JSON.stringify({ ...operation.body, updated_at: new Date().toISOString() }) });
    await hqRpc("hq_log_platform_action_v1", { p_actor_auth_user_id: actor.authUserId, p_platform: platform, p_action: `${body.action}_${decision}`, p_target_type: "platform_record", p_target_id: body.id, p_metadata: { decision, reason: body.reason || null } });
    return NextResponse.json({ ok: true, result });
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "Falha ao executar a acção." }, { status: 502 }); }
}
