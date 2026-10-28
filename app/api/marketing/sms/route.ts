import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization, hqRest, hqRpc } from "@/lib/hq-server";
import { campaignMessage, mozPhone, smsSegments, mozeBalance } from "@/lib/sms-campaigns";
import { dispatchSms, smsLiveEnabled, smsProviderConfig, type SmsCampaign } from "@/lib/sms-campaign-server";
export const dynamic = "force-dynamic";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const platformSlugs = ["deligo", "comunhao", "taomoz", "sarca", "mestre24", "exploremoz"];
async function context() {
  const c = await corporateAuthorization();
  return c && (c.isSuperAdmin || c.permissions.includes("marketing.sms")) ? c : null;
}
function scope(c: NonNullable<Awaited<ReturnType<typeof context>>>, app: string) {
  return platformSlugs.includes(app) && (c.isSuperAdmin || c.platformSlugs.includes(app));
}
function errorResponse() { return NextResponse.json({ error: "Operação SMS indisponível. Verifique a configuração, os consentimentos e o estado da campanha." }, { status: 409 }); }
export async function GET(request: NextRequest) {
  const c = await context();
  if (!c) return NextResponse.json({ error: "Sem permissão para SMS." }, { status: 403 });
  const apps = platformSlugs.filter(app => scope(c, app));
  const app = request.nextUrl.searchParams.get("app") || apps[0];
  if (!app || !scope(c, app)) return NextResponse.json({ error: "Plataforma não autorizada." }, { status: 403 });
  const offset = Math.max(0, Math.min(1000000, Number(request.nextUrl.searchParams.get("offset")) || 0));
  const campaignId = request.nextUrl.searchParams.get("campaign");
  try {
    if (campaignId) {
      if (!uuid.test(campaignId)) return NextResponse.json({ error: "ID inválido." }, { status: 400 });
      const campaign = (await hqRest(`sms_campaigns?id=eq.${campaignId}&app_slug=eq.${app}&select=*&limit=1`) as SmsCampaign[])[0];
      if (!campaign) return NextResponse.json({ error: "Campanha não encontrada." }, { status: 404 });
      const stats = await hqRpc("hq_sms_stats_v1", { p_id: campaignId }) as { counts: Record<string, number>; recordedCost: number };
      return NextResponse.json({ campaign, ...stats }, { headers: { "Cache-Control": "private, no-store" } });
    }
    const [campaigns, users] = await Promise.all([
      hqRest(`sms_campaigns?app_slug=eq.${app}&select=*&order=created_at.desc&limit=100`),
      hqRest(`global_user_platforms_v1?app_slug=eq.${app}&select=user_id,full_name,display_name,primary_phone,profile_status,membership_status&order=user_id.asc&limit=100&offset=${Math.floor(offset)}`),
    ]) as [SmsCampaign[], Record<string, unknown>[]];
    const ids = [...new Set(users.map(u => String(u.user_id)).filter(id => uuid.test(id)))];
    const consents = ids.length ? await hqRest(`sms_marketing_consents?app_slug=eq.${app}&user_id=in.(${ids.join(",")})&select=user_id,phone,allowed,updated_at`) : [];
    const balance = await smsProviderConfig().then(config => mozeBalance(config)).catch(() => null);
    return NextResponse.json({ apps, app, campaigns, users, consents, balance, offset, hasMore: users.length === 100, liveEnabled: smsLiveEnabled(), canSend: c.isSuperAdmin }, { headers: { "Cache-Control": "private, no-store" } });
  } catch { return errorResponse(); }
}
export async function POST(request: NextRequest) {
  const c = await context();
  if (!c) return NextResponse.json({ error: "Sem permissão para SMS." }, { status: 403 });
  // Cookie-authenticated mutations only from the same origin.
  if (request.headers.get("origin") !== request.nextUrl.origin) return NextResponse.json({ error: "Origem inválida." }, { status: 403 });
  try {
    const body = await request.json() as Record<string, unknown>;
    const app = String(body.app || "");
    if (!scope(c, app)) return NextResponse.json({ error: "Plataforma não autorizada." }, { status: 403 });
    if (body.action === "consent") {
      const userId = String(body.userId || ""), evidence = String(body.evidence || "").trim();
      if (!uuid.test(userId) || evidence.length < 5 || evidence.length > 1000 || typeof body.allowed !== "boolean") return NextResponse.json({ error: "Indique o utilizador e a prova ou motivo." }, { status: 400 });
      const user = (await hqRest(`global_user_platforms_v1?app_slug=eq.${app}&user_id=eq.${userId}&select=primary_phone&limit=1`))[0];
      const phone = user && mozPhone(String(user.primary_phone || ""));
      if (!phone) return NextResponse.json({ error: "Número moçambicano inválido ou utilizador indisponível." }, { status: 400 });
      await hqRest("sms_marketing_consents?on_conflict=app_slug,user_id,phone", { method: "POST", headers: { Prefer: "resolution=merge-duplicates,return=representation" }, body: JSON.stringify({ app_slug: app, user_id: userId, phone, allowed: body.allowed, evidence, recorded_by: c.actor.employee_id, updated_at: new Date().toISOString() }) });
      // Global suppression requires super admin; ordinary revocation still excludes this app.
      if (body.allowed === false && c.isSuperAdmin) await hqRest("sms_suppressions?on_conflict=phone", { method: "POST", headers: { Prefer: "resolution=merge-duplicates,return=representation" }, body: JSON.stringify({ phone, reason: evidence, recorded_by: c.actor.employee_id }) });
      await hqRest("sms_campaign_audit", { method: "POST", body: JSON.stringify({ actor_id: c.actor.employee_id, action: body.allowed ? "consent_recorded" : "consent_revoked", details: { app, user_id: userId, phone, evidence, allowed: body.allowed } }) });
      return NextResponse.json({ ok: true });
    }
    if (body.action === "create") {
      const title = String(body.title || "").trim(), message = campaignMessage(body.message), max = Number(body.maxRecipients);
      if (title.length < 3 || title.length > 120 || !Number.isInteger(max) || max < 1 || max > 10000) return NextResponse.json({ error: "Título ou limite de destinatários inválido." }, { status: 400 });
      const target = body.targetUserId ? String(body.targetUserId) : null;
      if (target && !uuid.test(target)) return NextResponse.json({ error: "Utilizador inválido." }, { status: 400 });
      const config = await smsProviderConfig();
      const [campaign] = await hqRest("sms_campaigns", { method: "POST", body: JSON.stringify({ app_slug: app, title, message, sender_id: config.sender, segments: smsSegments(message).segments, max_recipients: max, target_user_id: target, created_by: c.actor.employee_id }) });
      await hqRest("sms_campaign_audit", { method: "POST", body: JSON.stringify({ campaign_id: campaign.id, actor_id: c.actor.employee_id, action: "created" }) });
      return NextResponse.json({ campaign }, { status: 201 });
    }
    const id = String(body.id || "");
    if (!uuid.test(id)) return NextResponse.json({ error: "ID inválido." }, { status: 400 });
    const campaign = (await hqRest(`sms_campaigns?id=eq.${id}&app_slug=eq.${app}&select=*&limit=1`) as SmsCampaign[])[0];
    if (!campaign) return NextResponse.json({ error: "Campanha não encontrada." }, { status: 404 });
    if (["prepare", "send", "resume"].includes(String(body.action)) && !c.isSuperAdmin) return NextResponse.json({ error: "A autorização de envio exige Super Admin." }, { status: 403 });
    if (body.action === "prepare") {
      const count = await hqRpc("hq_sms_prepare_v1", { p_id: id, p_actor: c.actor.employee_id });
      return NextResponse.json({ ok: true, count });
    }
    if (["pause", "resume", "cancel"].includes(String(body.action))) {
      await hqRpc("hq_sms_control_v1", { p_id: id, p_actor: c.actor.employee_id, p_action: body.action });
      return NextResponse.json({ ok: true });
    }
    if (body.action === "send") return NextResponse.json(await dispatchSms(campaign, c.actor.employee_id));
    return NextResponse.json({ error: "Ação inválida." }, { status: 400 });
  } catch { return errorResponse(); }
}
