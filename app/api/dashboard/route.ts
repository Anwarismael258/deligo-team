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
    const [dashboardResponse, modulesResponse, mestre24Response, platformStatusResponse, testWalletsResponse] = await Promise.all([
      fetch(`${supabaseUrl()}/rest/v1/rpc/hq_dashboard_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      fetch(`${supabaseUrl()}/rest/v1/rpc/hq_platform_modules_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      fetch(`${supabaseUrl()}/rest/v1/rpc/hq_mestre24_module_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      fetch(`${supabaseUrl()}/rest/v1/platforms?select=slug,status,integration_status,last_sync_at,updated_at`, { headers: { ...rpcHeaders, "Accept-Profile": "hq" }, cache: "no-store", signal: AbortSignal.timeout(12_000) }),
      fetch(`${supabaseUrl()}/rest/v1/wallet_accounts?select=owner_user_id,available_balance_minor,metadata,status,currency_code&currency_code=eq.MZN&metadata->>test_mode=eq.true&metadata->>fictitious=eq.true`, { headers: { ...rpcHeaders, "Accept-Profile": "payments" }, cache: "no-store", signal: AbortSignal.timeout(12_000) }),
    ]);
    if (!dashboardResponse.ok || !modulesResponse.ok || !mestre24Response.ok) {
      console.error("HQ dashboard RPC failed", dashboardResponse.status, modulesResponse.status, mestre24Response.status);
      return NextResponse.json({ error: "O backend corporativo não respondeu correctamente." }, { status: 502 });
    }
    const executiveResponse = actor.role === "SUPER_ADMIN" ? await fetch(`${supabaseUrl()}/rest/v1/rpc/hq_executive_governance_v1`, { method: "POST", headers: rpcHeaders, body: "{}", cache: "no-store" }) : null;
    const [dashboard, modules, mestre24, executive, platformStatuses, testWalletRows, activeOrders, pendingKyc, openSupport, eventTickets, accountControls, openIncidents] = await Promise.all([
      dashboardResponse.json(), modulesResponse.json(), mestre24Response.json(), executiveResponse?.ok ? executiveResponse.json() : Promise.resolve(null),
      platformStatusResponse.ok ? platformStatusResponse.json() : Promise.resolve([]), testWalletsResponse.ok ? testWalletsResponse.json() : Promise.resolve([]),
      stagingRest("orders?select=id,status,total_amount,created_at,restaurant_id,courier_id&status=in.(pending,accepted,preparing,ready,courier_assigned,in_transit,arrived)&order=created_at.desc&limit=8").catch(() => []),
      stagingRest("profiles?select=id,full_name,role,kyc_status,approval_submitted_at,updated_at&role=in.(restaurant,courier)&kyc_status=eq.pending&order=updated_at.desc&limit=8").catch(() => []),
      stagingRest("support_tickets?select=id,reason,status,customer_name,updated_at&status=in.(open,pending,in_progress,escalated,waiting_customer)&order=updated_at.desc&limit=8").catch(() => []),
      stagingRest("marketing_event_tickets?select=id,status,price,deligo_commission,created_at&status=in.(sold,used)&order=created_at.desc&limit=200").catch(() => []),
      stagingRest("profiles?select=id,full_name,role,administrative_status,administrative_reason,updated_at&role=in.(client,customer,restaurant,courier)&order=updated_at.desc&limit=8").catch(() => []),
      stagingRest("order_disputes?select=*&status=not.in.(resolved,closed)&order=created_at.desc&limit=8").catch(() => []),
    ]) as [Record<string, unknown>, Record<string, unknown>, { platform: Record<string, unknown>; module: Record<string, unknown> }, unknown, Array<Record<string, unknown>>, Array<Record<string, unknown>>, Array<Record<string, unknown>>, Array<Record<string, unknown>>, Array<Record<string, unknown>>, Array<Record<string, unknown>>, Array<Record<string, unknown>>, Array<Record<string, unknown>>];
    const dashboardPlatforms = Array.isArray(dashboard.platforms) ? dashboard.platforms : [];
    const modulePlatforms = Array.isArray(modules.platforms) ? modules.platforms : [];
    const totalValue = Number(modules.totalValue || 0) + Number(mestre24.module.value || 0);
    const mergedModules = { ...modules, totalValue, platforms: [...modulePlatforms, mestre24.module] };
    const statusBySlug = new Map(platformStatuses.map((item) => [String(item.slug), item]));
    const enrichedPlatforms = [...dashboardPlatforms, mestre24.platform].map((item) => { const row = item as Record<string, unknown>; const status = statusBySlug.get(String(row.slug || "")); return { ...row, platform_status: status?.status || row.platform_status || "development", integration_status: status?.integration_status || (row.connected ? "connected" : "unknown"), last_sync_at: status?.last_sync_at || status?.updated_at || null }; });
    const testWallets = Array.isArray(testWalletRows) ? testWalletRows : [];
    const testOwners = new Set(testWallets.map((row) => String(row.owner_user_id || "")).filter(Boolean));
    const testWalletTotal = testWallets.reduce((sum, row) => sum + Number(row.available_balance_minor || 0), 0) / 100;
    const testMode = testWallets.length > 0 ? { unique_users: testOwners.size, wallet_count: testWallets.length, wallet_total: testWalletTotal, currency: "MZN", source: "payments.wallet_accounts", updated_at: new Date().toISOString() } : null;
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
    return NextResponse.json({ ...dashboard, platforms: enrichedPlatforms, modules: mergedModules, deligoOperations, test_mode: testMode, historical_total_value: totalValue, governance: actor.role === "SUPER_ADMIN" ? deligoTriunfalGovernance : null, executive }, {
      headers: { "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" },
    });
  } catch (error) {
    console.error("HQ dashboard connection failed", error);
    return NextResponse.json({ error: "Não foi possível ligar ao backend corporativo." }, { status: 502 });
  }
}
