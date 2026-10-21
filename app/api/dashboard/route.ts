import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { deligoTriunfalGovernance } from "@/lib/governance";
import { corporateActor, hqServiceKey, stagingRest, supabaseUrl } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

export async function GET() {
  const accessToken = (await cookies()).get("hq_access_token")?.value;
  if (!accessToken) return NextResponse.json({ error: "Sessão corporativa necessária." }, { status: 401 });
  const serviceKey = hqServiceKey();
  if (!serviceKey) {
    return NextResponse.json({ error: "A integração corporativa não está configurada neste ambiente." }, { status: 503 });
  }

  try {
    const actor = await corporateActor();
    if (!actor) return NextResponse.json({ error: "Sessão inválida, suspensa ou expirada." }, { status: 401 });
    const rpcHeaders: Record<string, string> = {
      apikey: serviceKey,
      "Content-Type": "application/json",
    };
    // Supabase secret keys authenticate through `apikey`; they must not be
    // echoed as a JWT in Authorization. Legacy service-role JWTs still need
    // the bearer header for older projects.
    if (!serviceKey.startsWith("sb_secret_")) {
      rpcHeaders.Authorization = `Bearer ${serviceKey}`;
    }
    const authorizationResponse = fetch(`${supabaseUrl()}/rest/v1/rpc/hq_actor_authorization_v1`, { method: "POST", headers: rpcHeaders, body: JSON.stringify({ p_employee_id: (actor as { employee_id: string }).employee_id }), cache: "no-store", signal: AbortSignal.timeout(12_000) });
    const [dashboardResponse, modulesResponse, mestre24Response, platformStatusResponse, authorization] = await Promise.all([
      fetch(`${supabaseUrl()}/rest/v1/rpc/hq_dashboard_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      fetch(`${supabaseUrl()}/rest/v1/rpc/hq_platform_modules_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      fetch(`${supabaseUrl()}/rest/v1/rpc/hq_mestre24_module_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      fetch(`${supabaseUrl()}/rest/v1/platforms?select=id,slug,name,platform_code,status,integration_status,last_sync_at,updated_at&order=name`, { headers: { ...rpcHeaders, "Accept-Profile": "hq" }, cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      authorizationResponse.then(response => response.ok ? response.json() : null),
    ]);
    if (!dashboardResponse.ok || !modulesResponse.ok || !mestre24Response.ok) {
      console.error("HQ dashboard RPC failed", dashboardResponse.status, modulesResponse.status, mestre24Response.status);
      return NextResponse.json({ error: "O backend corporativo não respondeu correctamente." }, { status: 502 });
    }
    const actorRole = String(actor.role || "").toUpperCase();
    const canViewDeligoFinance = ["SUPER_ADMIN", "FINANCE", "FINANCE_DIRECTOR"].includes(actorRole) && (["SUPER_ADMIN","FINANCE"].includes(actorRole) || Boolean(authorization?.is_super_admin) || (Array.isArray(authorization?.permissions) && authorization.permissions.includes("finance.view") && Array.isArray(authorization?.platform_slugs) && authorization.platform_slugs.includes("deligo")));
    const deligoFinanceResponse = canViewDeligoFinance ? fetch(`${supabaseUrl()}/rest/v1/rpc/hq_deligo_finance_summary_v1`, { method: "POST", headers: rpcHeaders, body: JSON.stringify({ p_actor_auth_user_id: actor.authUserId, p_from: null, p_to: null }), cache: "no-store", signal: AbortSignal.timeout(12_000) }) : null;
    const anonKey = process.env.SUPABASE_ANON_KEY;
    const canonicalFinanceResponse = canViewDeligoFinance && anonKey ? fetch(`${supabaseUrl()}/rest/v1/rpc/admin_canonical_finance_summary_v1`, { method: "POST", headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" }, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }) : null;
    const executiveResponse = ["SUPER_ADMIN","FINANCE"].includes(actor.role) ? await fetch(`${supabaseUrl()}/rest/v1/rpc/hq_executive_governance_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store" }) : null;
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
    // The canonical corporate wallet summary lives in the hq schema.  Calling
    // it as a public `hq_*` function returns 404/null and makes every Finance
    // card render "Indisponível" even when the ledger has data.
    const corporateRevenue = canViewDeligoFinance
      ? await fetch(`${supabaseUrl()}/rest/v1/rpc/corporate_revenue_summary_v1`, { method: "POST", headers: { ...rpcHeaders, "Accept-Profile": "hq", "Content-Profile": "hq" }, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }).then(response => response.ok ? response.json() : null).catch(() => null)
      : null;
    // The DeliGo app keeps the canonical user wallets in public.wallets.
    // Keep this separate from corporate profit: this is an informational total
    // for user wallets, never the corporate wallet or corporate revenue.
    const deligoWalletRows = canViewDeligoFinance
      ? await stagingRest("wallets?select=balance,currency&currency=eq.MZN&limit=10000").catch(() => null)
      : null;
    const deligoWalletTotal = Array.isArray(deligoWalletRows)
      ? deligoWalletRows.reduce((total, row) => total + Number((row as Record<string, unknown>).balance || 0), 0)
      : null;
    const financeSummary = canonicalFinance || legacyDeligoFinance;
    const summaryWithWallet = financeSummary
      ? { ...financeSummary, ...(deligoWalletTotal == null ? {} : { user_wallets_total: deligoWalletTotal }), ...(corporateRevenue && typeof corporateRevenue === "object" ? corporateRevenue : {}) }
      : (deligoWalletTotal == null && !corporateRevenue ? null : { ...(deligoWalletTotal == null ? {} : { user_wallets_total: deligoWalletTotal }), ...(corporateRevenue && typeof corporateRevenue === "object" ? corporateRevenue : {}) });
    const deligoFinance = summaryWithWallet
      ? { summary: summaryWithWallet, legacy: legacyDeligoFinance }
      : null;
    const dashboardPlatforms = Array.isArray(dashboard.platforms) ? dashboard.platforms : [];
    const modulePlatforms = Array.isArray(modules.platforms) ? modules.platforms : [];
    // Module catalogue values are not cash and must never appear as corporate
    // money. The official DeliGo Admin finance RPC is the only source for
    // DeliGo financial totals in the HQ overview.
    const totalValue = 0;
    const mergedModules = { ...modules, totalValue, platforms: [...modulePlatforms, mestre24.module] };
    const statusBySlug = new Map(platformStatuses.map((item) => [String(item.slug), item]));
    const cataloguePlatforms = platformStatuses.map((item) => ({
      slug: String(item.slug),
      name: String(item.name || item.slug),
      connected: ["connected", "operational"].includes(String(item.integration_status || item.status)),
      metrics: [],
    }));
    const sourcePlatforms = dashboardPlatforms.length ? dashboardPlatforms : cataloguePlatforms;
    const enrichedPlatforms = [...sourcePlatforms, mestre24.platform].filter((item, index, rows) => rows.findIndex(candidate => String(candidate.slug) === String(item.slug)) === index).map((item) => { const row = item as Record<string, unknown>; const status = statusBySlug.get(String(row.slug || "")); return { ...row, platform_status: status?.status || row.platform_status || "development", integration_status: status?.integration_status || (row.connected ? "connected" : "unknown"), last_sync_at: status?.last_sync_at || status?.updated_at || null }; });
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
    return NextResponse.json({ ...dashboard, platforms: enrichedPlatforms, modules: mergedModules, deligoOperations, deligoFinance, historical_total_value: totalValue, governance: ["SUPER_ADMIN","FINANCE"].includes(actorRole) ? deligoTriunfalGovernance : null, executive }, {
      headers: { "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" },
    });
  } catch (error) {
    console.error("HQ dashboard connection failed", error);
    return NextResponse.json({ error: "Não foi possível ligar ao backend corporativo." }, { status: 502 });
  }
}
