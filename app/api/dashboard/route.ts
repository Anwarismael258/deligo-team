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
    // DeliGo Eats still has canonical personal/customer/restaurant/courier
    // wallets in deligo.legacy_wallets. Keep those balances separate from corporate
    // revenue and use available_balance when the column exists; this endpoint
    // only exposes available funds, never subscription revenue.
    const deligoWalletRows = canViewDeligoFinance
      ? await stagingRest("legacy_wallets?select=id,balance,available_balance,pending_balance,currency,is_active,user_id,owner_id&currency=eq.MZN&limit=10000", { headers: { "Accept-Profile": "deligo", "Content-Profile": "deligo" } }).catch(() => stagingRest("legacy_wallets?select=id,balance,currency,is_active,user_id,owner_id&currency=eq.MZN&limit=10000", { headers: { "Accept-Profile": "deligo", "Content-Profile": "deligo" } }).catch(() => null))
      : null;
    const deligoProfileRows = canViewDeligoFinance
      ? await stagingRest("profiles?select=id,user_id,is_test_user&limit=10000").catch(() => [])
      : [];
    const knownDeligoUserIds = new Set(
      Array.isArray(deligoProfileRows)
        ? deligoProfileRows.flatMap(row => {
          const item = row as Record<string, unknown>;
          return [item.id, item.user_id].filter(Boolean).map(String);
        })
        : [],
    );
    const testUserIds = new Set(
      Array.isArray(deligoProfileRows)
        ? deligoProfileRows.filter(row => (row as Record<string, unknown>).is_test_user === true).flatMap(row => {
          const item = row as Record<string, unknown>;
          return [item.id, item.user_id].filter(Boolean).map(String);
        })
        : [],
    );
    // These two legacy wallets are explicitly identified as test accounts by
    // the business owner. Keep their rows intact for audit/history, but never
    // include them in the live DeliGo user-wallet total.
    const excludedKnownWalletUserIds = new Set([
      "5e5abc60-ecf5-416b-87a8-93cc0f30035a",
      "0efc4ae3-9b17-4695-940c-9c68b9473e12",
    ]);
    const activeDeligoWalletRows = Array.isArray(deligoWalletRows)
      ? deligoWalletRows.filter(row => {
        const item = row as Record<string, unknown>;
        const ownerId = String(item.user_id || item.owner_id || "");
        // Do not let orphaned/stale wallet rows inflate the Central total.
        // A real user wallet must be linked to a current DeliGo profile.
        return item.is_active === true
          && knownDeligoUserIds.has(ownerId)
          && !testUserIds.has(ownerId)
          && !excludedKnownWalletUserIds.has(ownerId);
      })
      : [];
    const deligoWalletAvailable = Array.isArray(deligoWalletRows)
      ? activeDeligoWalletRows.reduce((total, row) => {
        const item = row as Record<string, unknown>;
        return total + Number(item.available_balance ?? item.balance ?? 0);
      }, 0)
      : null;
    const deligoWalletPending = Array.isArray(deligoWalletRows)
      ? activeDeligoWalletRows.reduce((total, row) => total + Number((row as Record<string, unknown>).pending_balance || 0), 0)
      : null;
    const deligoWalletSources = activeDeligoWalletRows.map(row => {
      const item = row as Record<string, unknown>;
      return {
        wallet_id: item.id || null,
        user_id: item.user_id || item.owner_id || null,
        available_balance: Number(item.available_balance ?? item.balance ?? 0),
        pending_balance: Number(item.pending_balance || 0),
        currency: item.currency || "MZN",
        is_active: item.is_active === true,
      };
    }).filter(row => Boolean(row.user_id) && (row.available_balance !== 0 || row.pending_balance !== 0));
    const financialBreakdown = canViewDeligoFinance ? await (async () => {
      const rpc = await fetch(`${supabaseUrl()}/rest/v1/rpc/financial_platform_summary_v1`, { method: "POST", headers: { ...rpcHeaders, "Accept-Profile": "hq", "Content-Profile": "hq" }, body: "{}", cache: "no-store", signal: AbortSignal.timeout(2_500) }).then(response => response.ok ? response.json() : null).catch(() => null);
      const normalize = (value: Record<string, unknown>) => {
        const sourcePlatforms = Array.isArray(value.platforms) ? value.platforms as Array<Record<string, unknown>> : [];
        const platforms = sourcePlatforms.some(row => String(row.slug) === "deligo")
          ? sourcePlatforms.map(row => {
            if (String(row.slug) !== "deligo") return row;
            if (deligoWalletAvailable == null) return { ...row, wallet_sources: deligoWalletSources };
            const available = deligoWalletAvailable;
            const pending = deligoWalletPending ?? Number(row.wallet_pending || 0);
            return { ...row, wallet_available: available, wallet_pending: pending, funds_total: available + pending, wallet_sources: deligoWalletSources };
          })
          : deligoWalletAvailable == null
            ? sourcePlatforms
            : [...sourcePlatforms, { slug: "deligo", name: "DeliGo Eats", gross_confirmed: 0, central_revenue_confirmed: 0, provider_fees_confirmed: 0, wallet_available: deligoWalletAvailable, wallet_pending: deligoWalletPending ?? 0, funds_total: deligoWalletAvailable + (deligoWalletPending ?? 0), wallet_sources: deligoWalletSources }];
        // HQ employee wallets are personal balances. They are intentionally
        // excluded from the DeliGo custody aggregate and remain visible only
        // in the authenticated worker profile.
        const available = platforms.reduce((total, row) => total + Number(row.wallet_available || 0), 0) + Number(value.global_user_wallet_available || 0);
        const pending = platforms.reduce((total, row) => total + Number(row.wallet_pending || 0), 0) + Number(value.global_user_wallet_pending || 0);
        const centralRevenue = Number(value.central_revenue_confirmed || 0);
        return { ...value, platforms, user_wallets_available: available, user_wallets_pending: pending, total_funds_controlled_available: centralRevenue + available, total_funds_controlled_pending: pending };
      };
      if (rpc && typeof rpc === "object") return normalize(rpc as Record<string, unknown>);
      const profileRest = (schema: string, path: string) => fetch(`${supabaseUrl()}/rest/v1/${path}`, { headers: { ...rpcHeaders, "Accept-Profile": schema, "Content-Profile": schema }, cache: "no-store", signal: AbortSignal.timeout(4_000) }).then(response => response.ok ? response.json() : []).catch(() => []);
      const [platformRows, appRows, eventRows, walletRows] = await Promise.all([
        profileRest("hq", "platforms?select=id,slug,name&slug=in.(deligo,mestre24,sarca,comunhao,taomoz)"),
        profileRest("core", "apps?select=id,slug,name&slug=in.(deligo,mestre24,sarca,comunhao,taomoz)"),
        profileRest("hq", "platform_financial_events?select=platform_id,source_record_id,gross_amount,platform_fee,provider_fee,currency,payment_status,metadata&currency=eq.MZN&payment_status=eq.confirmed&limit=10000"),
        profileRest("payments", "wallet_accounts?select=app_id,owner_user_id,account_type,account_code,available_balance_minor,pending_balance_minor,currency_code,status,metadata&currency_code=eq.MZN&status=in.(active,suspended)&limit=10000"),
      ]) as [Array<Record<string, unknown>>, Array<Record<string, unknown>>, Array<Record<string, unknown>>, Array<Record<string, unknown>>];
      const appsBySlug = new Map(appRows.map(row => [String(row.slug), row]));
      const platformById = new Map(platformRows.map(row => [String(row.id), row]));
      const excluded = new Set(["platform", "system", "escrow"]);
      const platforms = ["deligo", "mestre24", "sarca", "comunhao", "taomoz"].map(slug => {
        const app = appsBySlug.get(slug);
        const platform = [...platformById.values()].find(row => String(row.slug) === slug);
        const platformId = String(platform?.id || "");
        const events = eventRows.filter(row => {
          const item = row as Record<string, unknown>;
          const metadata = item.metadata && typeof item.metadata === "object" ? item.metadata as Record<string, unknown> : {};
          return String(item.platform_id || "") === platformId
            && metadata.test_mode !== true
            && metadata.fictitious !== true
            && !String(item.source_record_id || "").startsWith("TEST-");
        });
        // DeliGo Eats uses deligo.legacy_wallets as its canonical user-wallet ledger;
        // do not count the same people again from payments.wallet_accounts.
        const wallets = slug === "deligo" ? [] : walletRows.filter(row => {
          const item = row as Record<string, unknown>;
          const metadata = item.metadata && typeof item.metadata === "object" ? item.metadata as Record<string, unknown> : {};
          const accountCode = String(item.account_code || "");
          const isTest = metadata.test_mode === true || metadata.fictitious === true || metadata.is_test_user === true
            || String(metadata.provisioning_source || "").startsWith("ecosystem_test")
            || accountCode.startsWith("TEST-");
          return String(item.app_id || "") === String(app?.id || "") && !excluded.has(String(item.account_type)) && !isTest;
        });
        const sum = (rows: Array<Record<string, unknown>>, key: string) => rows.reduce((total, row) => total + Number(row[key] || 0), 0);
        const walletAvailable = sum(wallets, "available_balance_minor") / 100;
        const walletPending = sum(wallets, "pending_balance_minor") / 100;
        const canonicalAvailable = slug === "deligo" && deligoWalletAvailable != null ? deligoWalletAvailable : walletAvailable;
        const canonicalPending = slug === "deligo" && deligoWalletPending != null ? deligoWalletPending : walletPending;
        return { slug, name: String(platform?.name || app?.name || slug), gross_confirmed: sum(events, "gross_amount"), central_revenue_confirmed: sum(events, "platform_fee"), provider_fees_confirmed: sum(events, "provider_fee"), wallet_available: canonicalAvailable, wallet_pending: canonicalPending, funds_total: canonicalAvailable + canonicalPending, ...(slug === "deligo" ? { wallet_sources: deligoWalletSources } : {}) };
      });
      const globalWallets = walletRows.filter(row => {
        const item = row as Record<string, unknown>;
        const metadata = item.metadata && typeof item.metadata === "object" ? item.metadata as Record<string, unknown> : {};
        const accountCode = String(item.account_code || "");
        const isTest = metadata.test_mode === true || metadata.fictitious === true || metadata.is_test_user === true
          || metadata.internal_only === true
          || String(metadata.provisioning_source || "").startsWith("ecosystem_test")
          || accountCode.startsWith("TEST-");
        return !item.app_id && item.owner_user_id && !excluded.has(String(item.account_type)) && !isTest;
      });
      const sum = (rows: Array<Record<string, unknown>>, key: string) => rows.reduce((total, row) => total + Number(row[key] || 0), 0) / 100;
      const platformWalletAvailable = platforms.reduce((total, row) => total + row.wallet_available, 0);
      const platformWalletPending = platforms.reduce((total, row) => total + row.wallet_pending, 0);
      const corporateWallet = Number((corporateRevenue as Record<string, unknown> | null)?.corporate_wallet_available || 0);
      const centralRevenue = platforms.reduce((total, row) => total + row.central_revenue_confirmed, 0);
      return { currency: "MZN", source: "hq.platform_financial_events + deligo.legacy_wallets + payments.wallet_accounts + hq.logical_wallets", platforms, corporate_wallet_available: corporateWallet, central_revenue_confirmed: centralRevenue, gross_platform_volume_confirmed: platforms.reduce((total, row) => total + row.gross_confirmed, 0), user_wallets_available: platformWalletAvailable + sum(globalWallets, "available_balance_minor"), user_wallets_pending: platformWalletPending + sum(globalWallets, "pending_balance_minor"), total_funds_controlled_available: centralRevenue + platformWalletAvailable + sum(globalWallets, "available_balance_minor"), total_funds_controlled_pending: platformWalletPending + sum(globalWallets, "pending_balance_minor"), legacy_revenue_included: false };
    })() : null;
    // Keep this separate from corporate profit: it is only an informational
    // total for user wallets, never the corporate wallet or corporate revenue.
    // Employee wallets are personal and must not inflate the DeliGo wallet
    // total shown in Finance. They remain available on the worker profile.
    const deligoWalletTotal = deligoWalletAvailable == null ? null : deligoWalletAvailable;
    const financeSummary = canonicalFinance || legacyDeligoFinance;
    const summaryWithWallet = financeSummary
      ? { ...financeSummary, ...(deligoWalletTotal == null ? {} : { user_wallets_total: deligoWalletTotal }), ...(corporateRevenue && typeof corporateRevenue === "object" ? corporateRevenue : {}) }
      : (deligoWalletTotal == null && !corporateRevenue ? null : { ...(deligoWalletTotal == null ? {} : { user_wallets_total: deligoWalletTotal }), ...(corporateRevenue && typeof corporateRevenue === "object" ? corporateRevenue : {}) });
    const deligoFinance = summaryWithWallet
      ? { summary: summaryWithWallet, breakdown: financialBreakdown, legacy: legacyDeligoFinance }
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
