import { NextRequest, NextResponse } from "next/server";
import { requireCorporatePermission, hqRpc, hqRest } from "@/lib/hq-server";
import { platformFunction, platformRest, platformRpc, signPlatformPath, type PlatformBackend } from "@/lib/platform-backends";
import { buildPlatformDecision, type PlatformDecision } from "@/lib/platform-decisions";

export const dynamic = "force-dynamic";
const allowed = ["deligo", "comunhao", "sarca", "taomoz", "mestre24"] as const;
const isPlatform = (value: string): value is PlatformBackend => allowed.includes(value as PlatformBackend);
const safeRest = async (platform: PlatformBackend, path: string, source: string, sourceErrors: Record<string, string>) => {
  try {
    return await platformRest(platform, path);
  } catch (error) {
    console.error("HQ_PLATFORM_SOURCE_UNAVAILABLE", { platform, source, error: error instanceof Error ? error.message : String(error) });
    sourceErrors[source] = "Fonte indisponível";
    return null;
  }
};
const mediaFields = ["storage_path", "file_path", "avatar_url", "profile_photo_url", "profile_image_url", "photo_url", "image_url", "document_url", "file_url", "selfie_url", "document_front_path", "document_back_path", "selfie_path", "proof_url", "photos", "documents", "files", "attachments"];
const signRecordMedia = async (platform: PlatformBackend, row: Record<string, unknown>) => { const copy = { ...row }; for (const field of mediaFields) { const value = copy[field]; if (typeof value === "string" && value) copy[field] = await signPlatformPath(platform, value); else if (Array.isArray(value)) copy[field] = await Promise.all(value.map(item => typeof item === "string" ? signPlatformPath(platform, item) : item)); } return copy; };
const signSnapshotMedia = async (platform: PlatformBackend, data: Record<string, unknown>) => { const result: Record<string, unknown> = { ...data }; for (const [key, value] of Object.entries(result)) if (Array.isArray(value)) result[key] = await Promise.all(value.map(item => item && typeof item === "object" ? signRecordMedia(platform, item as Record<string, unknown>) : item)); return result; };

export async function GET(request: NextRequest, context: { params: Promise<{ platform: string }> }) {
  const { platform } = await context.params;
  if (!isPlatform(platform)) return NextResponse.json({ error: "Plataforma inválida." }, { status: 400 });
  const authorization=await requireCorporatePermission("platform.manage",platform),actor=authorization?.actor;
  if (!actor) return NextResponse.json({ error: "Sem permissão para dados administrativos desta plataforma." }, { status: 403 });
  try {
    const sourceErrors: Record<string, string> = {};
    const data = platform === "mestre24"
      ? {
          professionals: await safeRest(platform, "professional_profiles?select=user_id,headline,verification_status,subscription_status,subscription_expires_at,trial_expires_at,rating,review_count,visible_in_marketplace,available_now,available_24h,created_at&order=created_at.desc&limit=250", "professionals", sourceErrors),
          profiles: await safeRest(platform, "profiles?select=user_id,account_type,full_name,phone_e164,city,district,active,created_at&order=created_at.desc&limit=250", "profiles", sourceErrors),
          subscriptions: await safeRest(platform, "subscription_cycles?select=*&order=created_at.desc&limit=250", "subscriptions", sourceErrors),
          requests: await safeRest(platform, "service_requests?select=*&order=created_at.desc&limit=250", "requests", sourceErrors),
          kyc: await safeRest(platform, "kyc_verifications?select=*&order=created_at.desc&limit=250", "kyc", sourceErrors),
          reports: await safeRest(platform, "reports?select=*&order=created_at.desc&limit=250", "reports", sourceErrors),
          reviews: await safeRest(platform, "reviews?select=*&order=created_at.desc&limit=250", "reviews", sourceErrors),
          promotions: await safeRest(platform, "featured_promotions?select=*&order=created_at.desc&limit=250", "promotions", sourceErrors),
          categories: await safeRest(platform, "categories?select=id,name,slug,parent_id,active,display_order&order=display_order.asc,name.asc", "categories", sourceErrors),
        }
      : platform === "sarca"
      ? {
          drivers: await safeRest(platform, "driver_profiles?select=*&order=updated_at.desc&limit=250", "drivers", sourceErrors),
          trips: await safeRest(platform, "trips?select=*&order=created_at.desc&limit=250", "trips", sourceErrors),
          kyc: await safeRest(platform, "driver_documents?select=*&order=created_at.desc&limit=250", "kyc", sourceErrors),
          driver_positions: await safeRest(platform, "driver_location_events?select=driver_user_id,latitude,longitude,accuracy_meters,recorded_at&order=recorded_at.desc&limit=250", "driver_positions", sourceErrors),
          rider_positions: await safeRest(platform, "rider_location_events?select=rider_user_id,trip_id,latitude,longitude,accuracy_meters,recorded_at&order=recorded_at.desc&limit=250", "rider_positions", sourceErrors),
        }
      : platform === "comunhao"
        ? { applications: await safeRest(platform, "church_applications?select=*&order=created_at.desc&limit=250", "applications", sourceErrors), subscriptions: await safeRest(platform, "church_subscriptions?select=*&order=created_at.desc&limit=100", "subscriptions", sourceErrors), subscription_plans: await safeRest(platform, "subscription_plans?select=code,name,description,price_mzn,currency_code,billing_cycle_days,member_limit,admin_limit,features,is_public,is_paid,is_active,sort_order&is_active=eq.true&order=sort_order.asc,code.asc", "subscription_plans", sourceErrors), notifications: await safeRest(platform, "internal_notifications?select=*&order=created_at.desc&limit=100", "notifications", sourceErrors) }
        : platform === "taomoz"
          ? { users: await safeRest(platform, "profiles?select=id,full_name,phone,account_status,created_at&order=created_at.desc&limit=100", "users", sourceErrors), kyc: await safeRest(platform, "kyc_submissions?select=*&status=eq.pending&order=created_at.desc&limit=100", "kyc", sourceErrors), products: await safeRest(platform, "products?select=id,name,moderation_status,is_active,created_at&order=created_at.desc&limit=100", "products", sourceErrors), orders: await safeRest(platform, "orders?select=id,order_number,status,payment_status,grand_total,created_at&order=created_at.desc&limit=100", "orders", sourceErrors), disputes: await safeRest(platform, "disputes?select=*&order=created_at.desc&limit=100", "disputes", sourceErrors), withdrawals: await safeRest(platform, "money_operations?select=*&type=eq.withdrawal&order=created_at.desc&limit=100", "withdrawals", sourceErrors) }
          : { profiles: await safeRest(platform, "profiles?select=id,full_name,phone,role,kyc_status,is_blocked,created_at&order=created_at.desc&limit=250", "profiles", sourceErrors), orders: await safeRest(platform, "orders?select=*&order=created_at.desc&limit=100", "orders", sourceErrors), restaurants: await safeRest(platform, "restaurants?select=*&order=created_at.desc&limit=100", "restaurants", sourceErrors), couriers: await safeRest(platform, "couriers?select=*&order=created_at.desc&limit=100", "couriers", sourceErrors), support: await safeRest(platform, "support_tickets?select=*&order=updated_at.desc&limit=100", "support", sourceErrors), marketing: await safeRest(platform, "marketing_campaigns?select=*&order=created_at.desc&limit=100", "marketing", sourceErrors), disputes: await safeRest(platform, "order_disputes?select=*&order=created_at.desc&limit=100", "disputes", sourceErrors), wallets: await safeRest(platform, "wallets?select=id,owner_id,balance,currency,created_at&order=created_at.desc&limit=100", "wallets", sourceErrors), audit: await safeRest(platform, "admin_actions_log?select=*&order=created_at.desc&limit=100", "audit", sourceErrors) };
    return NextResponse.json({ platform, data: await signSnapshotMedia(platform, data as Record<string, unknown>), sourceErrors, checkedAt: new Date().toISOString() }, { headers: { "Cache-Control": "private, no-store" } });
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
    if (platform === "sarca") {
      const cases = await hqRest(`platform_kyc_cases?select=id&source_schema=eq.sarca&source_table=eq.driver_documents&source_record_id=eq.${encodeURIComponent(body.id)}`) as { id: string }[];
      if (!cases[0]) return NextResponse.json({ error: "Selecione um documento KYC para rever." }, { status: 400 });
      const employees = await hqRest(`employees?select=auth_user_id&id=eq.${encodeURIComponent(actor.employee_id)}&status=eq.active`) as { auth_user_id: string }[];
      if (!employees[0]?.auth_user_id) return NextResponse.json({ error: "Identidade do trabalhador indisponível." }, { status: 403 });
      const result = await hqRpc("hq_decide_platform_kyc_v1", { p_case_id: cases[0].id, p_actor_auth_user_id: employees[0].auth_user_id, p_decision: decision, p_reason: body.reason?.trim() || null });
      return NextResponse.json({ ok: true, result });
    }
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
