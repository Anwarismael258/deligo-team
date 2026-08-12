import { NextRequest, NextResponse } from "next/server";
import { requireCorporatePermission, hqRpc } from "@/lib/hq-server";
import { platformFunction, platformRest, platformRpc, signPlatformPath, type PlatformBackend } from "@/lib/platform-backends";
import { buildPlatformDecision, type PlatformDecision } from "@/lib/platform-decisions";

export const dynamic = "force-dynamic";
const allowed = ["deligo", "comunhao", "sarca", "taomoz", "mestre24"] as const;
const isPlatform = (value: string): value is PlatformBackend => allowed.includes(value as PlatformBackend);
const safeRest = async (platform: PlatformBackend, path: string) => { try { return await platformRest(platform, path); } catch { return []; } };
const mediaFields = ["photo_url", "image_url", "document_url", "file_url", "selfie_url", "document_front_path", "document_back_path", "selfie_path", "proof_url", "photos", "documents", "files", "attachments"];
const signRecordMedia = async (platform: PlatformBackend, row: Record<string, unknown>) => { const copy = { ...row }; for (const field of mediaFields) { const value = copy[field]; if (typeof value === "string" && value) copy[field] = await signPlatformPath(platform, value); else if (Array.isArray(value)) copy[field] = await Promise.all(value.map(item => typeof item === "string" ? signPlatformPath(platform, item) : item)); } return copy; };
const signSnapshotMedia = async (platform: PlatformBackend, data: Record<string, unknown>) => { const result: Record<string, unknown> = { ...data }; for (const [key, value] of Object.entries(result)) if (Array.isArray(value)) result[key] = await Promise.all(value.map(item => item && typeof item === "object" ? signRecordMedia(platform, item as Record<string, unknown>) : item)); return result; };

export async function GET(request: NextRequest, context: { params: Promise<{ platform: string }> }) {
  const { platform } = await context.params;
  if (!isPlatform(platform)) return NextResponse.json({ error: "Plataforma inválida." }, { status: 400 });
  const authorization=await requireCorporatePermission("platform.manage",platform),actor=authorization?.actor;
  if (!actor) return NextResponse.json({ error: "Sem permissão para dados administrativos desta plataforma." }, { status: 403 });
  try {
    const data = platform === "mestre24"
      ? {
          professionals: await safeRest(platform, "professional_profiles?select=user_id,headline,verification_status,subscription_status,subscription_expires_at,trial_expires_at,rating,review_count,visible_in_marketplace,available_now,available_24h,created_at&order=created_at.desc&limit=250"),
          profiles: await safeRest(platform, "profiles?select=user_id,account_type,full_name,phone_e164,city,district,active,created_at&order=created_at.desc&limit=250"),
          subscriptions: await safeRest(platform, "subscription_cycles?select=*&order=created_at.desc&limit=250"),
          requests: await safeRest(platform, "service_requests?select=*&order=created_at.desc&limit=250"),
          kyc: await safeRest(platform, "kyc_verifications?select=*&order=created_at.desc&limit=250"),
          reports: await safeRest(platform, "reports?select=*&order=created_at.desc&limit=250"),
          reviews: await safeRest(platform, "reviews?select=*&order=created_at.desc&limit=250"),
          promotions: await safeRest(platform, "featured_promotions?select=*&order=created_at.desc&limit=250"),
          categories: await safeRest(platform, "categories?select=id,name,slug,parent_id,active,display_order&order=display_order.asc,name.asc"),
        }
      : platform === "sarca"
      ? await platformFunction(platform, "admin-get-dashboard")
      : platform === "comunhao"
        ? { applications: await safeRest(platform, "church_applications?select=*&order=created_at.desc&limit=250"), subscriptions: await safeRest(platform, "church_subscriptions?select=*&order=created_at.desc&limit=100"), subscription_plans: await safeRest(platform, "subscription_plans?select=code,name,description,price_mzn,currency_code,billing_cycle_days,member_limit,admin_limit,features,is_public,is_paid,is_active,sort_order&is_active=eq.true&order=sort_order.asc,code.asc"), notifications: await safeRest(platform, "internal_notifications?select=*&order=created_at.desc&limit=100") }
        : platform === "taomoz"
          ? { users: await safeRest(platform, "profiles?select=id,full_name,phone,account_status,created_at&order=created_at.desc&limit=100"), kyc: await safeRest(platform, "kyc_submissions?select=*&status=eq.pending&order=created_at.desc&limit=100"), products: await safeRest(platform, "products?select=id,name,moderation_status,is_active,created_at&order=created_at.desc&limit=100"), orders: await safeRest(platform, "orders?select=id,order_number,status,payment_status,grand_total,created_at&order=created_at.desc&limit=100"), disputes: await safeRest(platform, "disputes?select=*&order=created_at.desc&limit=100"), withdrawals: await safeRest(platform, "money_operations?select=*&type=eq.withdrawal&order=created_at.desc&limit=100") }
          : { profiles: await safeRest(platform, "profiles?select=id,full_name,phone,role,kyc_status,is_blocked,created_at&order=created_at.desc&limit=250"), orders: await safeRest(platform, "orders?select=*&order=created_at.desc&limit=100"), restaurants: await safeRest(platform, "restaurants?select=*&order=created_at.desc&limit=100"), couriers: await safeRest(platform, "couriers?select=*&order=created_at.desc&limit=100"), support: await safeRest(platform, "support_tickets?select=*&order=updated_at.desc&limit=100"), marketing: await safeRest(platform, "marketing_campaigns?select=*&order=created_at.desc&limit=100"), disputes: await safeRest(platform, "order_disputes?select=*&order=created_at.desc&limit=100"), wallets: await safeRest(platform, "wallets?select=id,owner_id,balance,currency,created_at&order=created_at.desc&limit=100"), audit: await safeRest(platform, "admin_actions_log?select=*&order=created_at.desc&limit=100") };
    return NextResponse.json({ platform, data: await signSnapshotMedia(platform, data as Record<string, unknown>), checkedAt: new Date().toISOString() }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "Falha ao carregar a plataforma." }, { status: 502 }); }
}

export async function PATCH(request: NextRequest, context: { params: Promise<{ platform: string }> }) {
  const { platform } = await context.params;
  if (!isPlatform(platform)) return NextResponse.json({ error: "Plataforma inválida." }, { status: 400 });
  const authorization=await requireCorporatePermission("platform.manage",platform),actor=authorization?.actor;
  if (!actor) return NextResponse.json({ error: "A decisão exige permissão na plataforma atribuída." }, { status: 403 });
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
