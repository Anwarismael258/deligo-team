import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRpc } from "@/lib/hq-server";
import { platformFunction, platformRest, platformRpc, type PlatformBackend } from "@/lib/platform-backends";

export const dynamic = "force-dynamic";
const allowed = ["deligo", "comunhao", "sarca", "taomoz"] as const;
const isPlatform = (value: string): value is PlatformBackend => allowed.includes(value as PlatformBackend);

export async function GET(request: NextRequest, context: { params: Promise<{ platform: string }> }) {
  const actor = await corporateActor();
  const { platform } = await context.params;
  if (!actor) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401 });
  if (!isPlatform(platform)) return NextResponse.json({ error: "Plataforma inválida." }, { status: 400 });
  try {
    const data = platform === "sarca"
      ? await platformFunction(platform, "admin-get-dashboard")
      : platform === "comunhao"
        ? { applications: await platformRest(platform, "church_applications?select=*&order=created_at.desc&limit=250") }
        : platform === "taomoz"
          ? { users: await platformRest(platform, "profiles?select=id,full_name,phone,account_status,created_at&order=created_at.desc&limit=100"), kyc: await platformRest(platform, "kyc_submissions?select=*&status=eq.pending&order=created_at.desc&limit=100"), products: await platformRest(platform, "products?select=id,name,moderation_status,is_active,created_at&order=created_at.desc&limit=100"), orders: await platformRest(platform, "orders?select=id,order_number,status,payment_status,grand_total,created_at&order=created_at.desc&limit=100") }
          : { profiles: await platformRest(platform, "profiles?select=id,full_name,phone,role,kyc_status,is_blocked,created_at&order=created_at.desc&limit=250"), orders: await platformRest(platform, "orders?select=*&order=created_at.desc&limit=100"), restaurants: await platformRest(platform, "restaurants?select=*&order=created_at.desc&limit=100"), couriers: await platformRest(platform, "couriers?select=*&order=created_at.desc&limit=100") };
    return NextResponse.json({ platform, data, checkedAt: new Date().toISOString() }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "Falha ao carregar a plataforma." }, { status: 502 }); }
}

export async function PATCH(request: NextRequest, context: { params: Promise<{ platform: string }> }) {
  const actor = await corporateActor();
  const { platform } = await context.params;
  if (!actor) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401 });
  if (!isPlatform(platform)) return NextResponse.json({ error: "Plataforma inválida." }, { status: 400 });
  const body = await request.json() as { action?: string; id?: string; reason?: string; payload?: Record<string, unknown> };
  if (!body.action || !body.id) return NextResponse.json({ error: "Acção e registo são obrigatórios." }, { status: 400 });
  try {
    let result: unknown;
    if (platform === "sarca") result = await platformFunction(platform, body.action === "review_driver" ? "admin-review-driver-onboarding" : body.action === "account_status" ? "admin-update-account-status" : body.action, { id: body.id, reason: body.reason, ...body.payload });
    else if (platform === "comunhao" && body.action === "review_application") result = await platformRpc(platform, "review_church_application", { p_application_id: body.id, p_action: body.payload?.decision || "correction", p_notes: body.reason || null });
    else if (platform === "taomoz" && body.action === "review_kyc") result = await platformRpc(platform, "admin_review_kyc", { submission_id: body.id, decision: body.payload?.decision || "rejected", reason: body.reason || "" });
    else if (platform === "deligo" && ["approve", "reject", "correction"].includes(body.action)) result = await platformRest(platform, `profiles?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify({ kyc_status: body.action === "approve" ? "approved" : body.action === "reject" ? "rejected" : "pending", kyc_rejection_reason: body.reason || null, updated_at: new Date().toISOString() }) });
    else return NextResponse.json({ error: "Acção ainda não configurada para esta plataforma." }, { status: 400 });
    await hqRpc("hq_log_platform_action_v1", { p_actor_auth_user_id: actor.authUserId, p_platform: platform, p_action: body.action, p_target_type: "platform_record", p_target_id: body.id, p_metadata: { reason: body.reason || null } });
    return NextResponse.json({ ok: true, result });
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "Falha ao executar a acção." }, { status: 502 }); }
}
