import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { deligoTriunfalGovernance } from "@/lib/governance";
import { corporateActor, stagingRest, supabaseUrl } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

export async function GET() {
  const accessToken = (await cookies()).get("hq_access_token")?.value;
  if (!accessToken) return NextResponse.json({ error: "Sessão corporativa necessária." }, { status: 401 });
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceKey) {
    return NextResponse.json({ error: "A integração corporativa não está configurada neste ambiente." }, { status: 503 });
  }

  try {
    const actor = await corporateActor();
    if (!actor) return NextResponse.json({ error: "Sessão inválida, suspensa ou expirada." }, { status: 401 });
    const rpcHeaders = {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      };
    const authorizationResponse = fetch(`${supabaseUrl()}/rest/v1/rpc/hq_actor_authorization_v1`, { method: "POST", headers: rpcHeaders, body: JSON.stringify({ p_employee_id: (actor as { employee_id: string }).employee_id }), cache: "no-store", signal: AbortSignal.timeout(12_000) });
    const [dashboardResponse, modulesResponse, mestre24Response, platformStatusResponse, authorization] = await Promise.all([
      fetch(`${supabaseUrl()}/rest/v1/rpc/hq_dashboard_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      fetch(`${supabaseUrl()}/rest/v1/rpc/hq_platform_modules_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      fetch(`${supabaseUrl()}/rest/v1/rpc/hq_mestre24_module_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      fetch(`${supabaseUrl()}/rest/v1/platforms?select=slug,status,integration_status,last_sync_at,updated_at`, { headers: { ...rpcHeaders, "Accept-Profile": "hq" }, cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      authorizationResponse.then(response => response.ok ? response.json() : null),
    ]);
    if (!dashboardResponse.ok || !modulesResponse.ok || !mestre24Response.ok) {
      console.error("HQ dashboard RPC failed", dashboardResponse.status, modulesResponse.status, mestre24Response.status);
      return NextResponse.json({ error: "O backend corporativo não respondeu correctamente." }, { status: 502 });
    }
    const canViewDeligoFinance = ["SUPER_ADMIN", "FINANCE"].includes(actor.role) && (actor.role === "SUPER_ADMIN" || Boolean(authorization?.is_super_admin) || (Array.isArray(authorization?.permissions) && authorization.permissions.includes("finance.view") && Array.isArray(authorization?.platform_slugs) && authorization.platform_slugs.includes("deligo")));
    const deligoFinanceResponse = canViewDeligoFinance ? fetch(`${supabaseUrl()}/rest/v1/rpc/hq_deligo_finance_summary_v1`, { method: "POST", headers: rpcHeaders, body: JSON.stringify({ p_actor_auth_user_id: actor.authUserId, p_from: null, p_to: null }), cache: "no-store", signal: AbortSignal.timeout(12_000) }) : null;
    const anonKey = process.env.SUPABASE_ANON_KEY;
    const canonicalFinanceResponse = canViewDeligoFinance && anonKey ? fetch(`${supabaseUrl()}/rest/v1/rpc/admin_canonical_finance_summary_v1`, { method: "POST", headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" }, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }) : null;
    const executiveResponse = actor.role === "SUPER_ADMIN" ? await fetch(`${supabaseUrl()}/rest/v1/rpc/hq_executive_governance_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store" }) : null;
    const [dashboard, modules, mestre24, executive, platformStatuses, financeResponses, activeOrders, pendingKyc, openSupport, eventTickets, accountControls, openIncidents] = await Promise.all([
      dashboardResponse.json(), modulesResponse.json(), mestre24Response.json(), executiveResponse?.ok ? executiveResponse.json() : Promise.resolve(null),
      platformStatusResponse.ok ? platformStatusResponse.json() : Promise.resolve([]),
      Promise.all([deligoFinanceResponse?.then(response => response.ok ? response.json() : null) || Promise.resolve(null), canonicalFinanceResponse?.then(response => response.ok ? response.json() : null) || Promise.resolve(null)]),
      stagingRest("orders?select=id,status,total_amount,created_at,restaurant_id,courier_id&status=in.(pending,accepted,preparing,ready,courier_assigned,in_transit,arrived)&order=created_at.desc&limit=8").catch(() => []),
      stagingRest("profiles?select=id,full_name,role,kyc_status,approval_submitted_at,updated_at&role=in.(restaurant,courier)&kyc_status=eq.pending&order=updated_at.desc&limit=8").catch(() => []),
      stagingRest("support_tickets?select=id,reason,status,customer_name,updated_at&status=in.(open,pending,in_progress,escalated,waiting_customer)&order=updated_at.desc&limit=8").catch(() => []),
      stagingRest("marketing_event_tickets?select=id,status,price,deligo_commission,created_at&status=in.(sold,used)&order=created_at.desc&limit=200").catch(() => []),
      stagingRest("profiles?select=id,full_name,role,administrative_status,administrative_reason,updated_at&role=in.(client,customer,restaurant,courier)&order=updated_at.desc&limit=8").catch(() => []),
      stagingRest("order_disputes?select=*&status=not.in.(resolved,closed)&order=created_at.desc&limit=8").catch(() => []),
    ]) as [Record<string, unknown>, Record<string, unknown>, { platform: Record<string, unknown>; module: Record<string, unknown> }, unknown, Array<Record<string, unknown>>, [Record<string, unknown> | null, Record<string, unknown> | null], Array<Record<string, unknown>>, Array<Record<string, unknown>>, Array<Record<string, unknown>>, Array<Record<string, unknown>>, Array<Record<string, unknown>>, Array<Record<string, unknown>>];
    const [legacyDeligoFinance, canonicalFinance] = financeResponses as [Record<string, unknown> | null, Record<string, unknown> | null];
    const deligoFinance = canonicalFinance ? { summary: canonicalFinance, legacy: legacyDeligoFinance } : legacyDeligoFinance;
    const dashboardPlatforms = Array.isArray(dashboard.platforms) ? dashboard.platforms : [];
    const modulePlatforms = Array.isArray(modules.platforms) ? modules.platforms : [];
    // Module catalogue values are not cash and must never appear as corporate
    // money. The official DeliGo Admin finance RPC is the only source for
    // DeliGo financial totals in the HQ overview.
    const totalValue = 0;
    const mergedModules = { ...modules, totalValue, platforms: [...modulePlatforms, mestre24.module] };
    const statusBySlug = new Map(platformStatuses.map((item) => [String(item.slug), item]));
    const enrichedPlatforms = [...dashboardPlatforms, mestre24.platform].map((item) => { const row = item as Record<string, unknown>; const status = statusBySlug.get(String(row.slug || "")); return { ...row, platform_status: status?.status || row.platform_status || "development", integration_status: status?.integration_status || (row.connected ? "connected" : "unknown"), last_sync_at: status?.last_sync_at || status?.updated_at || null }; });
    const now = Date.now();
    const deligoOperations = {
      activeOrders, pendingKyc, openSupport, accountControls, openIncidents,
      summary: {
        activeOrders: activeOrders.length,
        attentionOrders: activeOrders.filter((item) => now - new Date(String(item.created_at || now)).getTime() > 45 * 60 * 1000).length,
        pendingKyc: pendingKyc.length,
        openSupport: openSupport.length,
        ticketsSold: eventTickets.length,
        ticketRevenue: eventTickets.reduce((sum, item) => sum + Number(item.price || 0), 0),
        ticketProfit: eventTickets.reduce((sum, item) => sum + Number(item.deligo_commission || 0), 0),
      },
    };
    return NextResponse.json({ ...dashboard, platforms: enrichedPlatforms, modules: mergedModules, deligoOperations, deligoFinance, historical_total_value: totalValue, governance: actor.role === "SUPER_ADMIN" ? deligoTriunfalGovernance : null, executive }, {
      headers: { "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" },
    });
  } catch (error) {
    console.error("HQ dashboard connection failed", error);
    return NextResponse.json({ error: "Não foi possível ligar ao backend corporativo." }, { status: 502 });
  }
}
