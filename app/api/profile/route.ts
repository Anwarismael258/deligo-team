import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRest, hqServiceKey, stagingRest, supabaseUrl } from "@/lib/hq-server";
import { detectMozambiqueWalletOperator } from "@/lib/mozambique-wallet";

const paysuiteAvailable = () => (process.env.PAYSUITE_ENABLED === "true" && Boolean(process.env.PAYSUITE_API_TOKEN)) || Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_ANON_KEY);

function privilegedHeaders(key: string, profile: string) {
  const result: Record<string, string> = {
    apikey: key,
    "Accept-Profile": profile,
    "Content-Profile": profile,
    "Content-Type": "application/json",
  };
  if (!key.startsWith("sb_secret_")) result.Authorization = `Bearer ${key}`;
  return result;
}

async function paymentsRest(key: string, path: string) {
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, {
    headers: privilegedHeaders(key, "payments"),
    cache: "no-store",
  });
  if (!response.ok) throw new Error(await response.text());
  return response.json();
}

async function coreRest(key: string, path: string) {
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, {
    headers: privilegedHeaders(key, "core"),
    cache: "no-store",
  });
  if (!response.ok) throw new Error(await response.text());
  return response.json();
}

function mapCanonicalWallet(wallet: Record<string, unknown>, app?: Record<string, unknown>) {
  const metadata = (wallet.metadata && typeof wallet.metadata === "object" ? wallet.metadata : {}) as Record<string, unknown>;
  return {
    id: wallet.id,
    platform_slug: app?.slug || null,
    platform_name: app?.name || null,
    wallet_code: wallet.account_code,
    account_type: wallet.account_type,
    source_kind: "canonical",
    currency: wallet.currency_code,
    available_amount: Number(wallet.available_balance_minor || 0) / 100,
    pending_amount: Number(wallet.pending_balance_minor || 0) / 100,
    reserved_amount: Number(wallet.reserved_balance_minor || 0) / 100,
    // The shared Supabase Edge Function may own the provider integration, so
    // older wallet rows do not always carry a provider_integration marker.
    // The withdrawal endpoint remains authoritative and will reject a real
    // provider failure; do not hide a valid personal balance in the UI.
    withdrawal_enabled: metadata.withdrawal_disabled !== true && paysuiteAvailable(),
  };
}

export async function GET() {
  try {
    const actor = await corporateActor();
    const key = hqServiceKey();
    if (!actor || !key) return NextResponse.json({ error: "Sessão inválida." }, { status: 401 });

    // The employee profile is the primary resource. Wallet adapters are
    // optional: a missing legacy table or a temporarily unavailable app
    // schema must not make the profile page unusable.
    const [profileResult, employeeResult] = await Promise.allSettled([
      hqRest(`employee_display_profiles?employee_id=eq.${encodeURIComponent(actor.employee_id)}&select=*`),
      hqRest(`employees?id=eq.${encodeURIComponent(actor.employee_id)}&select=auth_user_id`),
    ]);
    const profileRows = profileResult.status === "fulfilled" ? profileResult.value : [];
    // A login token can belong to a legacy Auth identity while the employee
    // record already points to the canonical identity used by DeliGo's
    // personal wallet. Resolve the wallet owner from the employee record so
    // the profile never displays an unrelated zero-balance legacy wallet.
    const employeeRows = employeeResult.status === "fulfilled" ? employeeResult.value : [];
    if (profileResult.status === "rejected") console.warn("employee display profile unavailable", profileResult.reason);
    if (employeeResult.status === "rejected") console.warn("employee wallet owner unavailable", employeeResult.reason);
    const walletOwnerId = String(employeeRows?.[0]?.auth_user_id || actor.authUserId);
    const [legacyResult, canonicalResult, appsResult, hqEmployeeWalletResult] = await Promise.allSettled([
      stagingRest(`wallets?user_id=eq.${encodeURIComponent(walletOwnerId)}&select=id,balance,currency&limit=1`) as Promise<Array<Record<string, unknown>>>,
      // A carteira pessoal é consolidada por utilizador, não por um único
      // account_type. O mesmo trabalhador pode ter contas pessoais de DeliGo,
      // SARCA, Mestre24, estafeta ou comerciante; a carteira CORPORATE_MZN
      // continua fora deste filtro porque não tem owner_user_id.
      paymentsRest(key, `wallet_accounts?owner_user_id=eq.${encodeURIComponent(walletOwnerId)}&status=eq.active&select=id,app_id,account_code,account_type,currency_code,available_balance_minor,pending_balance_minor,reserved_balance_minor,metadata`),
      coreRest(key, "apps?select=id,slug,name"),
      hqRest(`logical_wallets?owner_user_id=eq.${encodeURIComponent(actor.authUserId)}&wallet_type=eq.employee&status=eq.active&currency=eq.MZN&select=id,wallet_code,wallet_type,currency,available_amount,pending_amount,reserved_amount`),
    ]);
    const legacy = legacyResult.status === "fulfilled" ? legacyResult.value : [];
    const canonical = canonicalResult.status === "fulfilled" ? canonicalResult.value : [];
    const apps = appsResult.status === "fulfilled" ? appsResult.value : [];
    const hqEmployeeWallets = hqEmployeeWalletResult.status === "fulfilled" ? hqEmployeeWalletResult.value : [];
    if (legacyResult.status === "rejected") console.warn("profile legacy wallet unavailable", legacyResult.reason);
    if (canonicalResult.status === "rejected") console.warn("profile canonical wallets unavailable", canonicalResult.reason);
    if (appsResult.status === "rejected") console.warn("profile app catalog unavailable", appsResult.reason);
    const profile = profileRows?.[0] || null;
    const appById = new Map((Array.isArray(apps) ? apps : []).map((app: Record<string, unknown>) => [String(app.id), app]));
    const canonicalWallets = (Array.isArray(canonical) ? canonical : [])
      .filter((wallet: Record<string, unknown>) => {
        const metadata = wallet.metadata && typeof wallet.metadata === "object" ? wallet.metadata as Record<string, unknown> : {};
        const accountCode = String(wallet.account_code || "");
        return metadata.test_mode !== true
          && metadata.fictitious !== true
          && metadata.is_test_user !== true
          && !accountCode.startsWith("TEST-");
      })
      .map((wallet: Record<string, unknown>) => mapCanonicalWallet(wallet, appById.get(String(wallet.app_id))))
      .filter((wallet: Record<string, unknown>) => String(wallet.currency || "MZN") === "MZN");

    const hqPersonalWallets = (Array.isArray(hqEmployeeWallets) ? hqEmployeeWallets : []).map((wallet: Record<string, unknown>) => ({
      id: `hq-${String(wallet.id)}`,
      platform_slug: null,
      platform_name: "DeliGo Central",
      wallet_code: wallet.wallet_code,
      account_type: "employee",
      source_kind: "hq_corporate_profit_transfer",
      currency: wallet.currency || "MZN",
      available_amount: Number(wallet.available_amount || 0),
      pending_amount: Number(wallet.pending_amount || 0),
      reserved_amount: Number(wallet.reserved_amount || 0),
      withdrawal_enabled: paysuiteAvailable(),
    }));
    // The founder's old 10 MZN display balance was created by the previous
    // corporate-withdrawal experiment and is not a valid personal balance.
    // Keep its ledger history intact, but do not expose or make it withdrawable
    // until a reconciled internal transfer creates a new personal balance.
    const visibleHqPersonalWallets = hqPersonalWallets.filter((wallet) => !(
      actor.employee_code === "DG-0001"
      && Number(wallet.available_amount || 0) === 10
      && Number(wallet.pending_amount || 0) === 0
      && Number(wallet.reserved_amount || 0) === 0
    ));
    const hqPersonalWalletHasFunds = visibleHqPersonalWallets.some((wallet) =>
      Number(wallet.available_amount || 0) > 0 || Number(wallet.pending_amount || 0) > 0 || Number(wallet.reserved_amount || 0) > 0,
    );

    // The old DeliGo wallet is a display fallback until its balance is migrated
    // into the canonical PaySuite wallet. Never add both representations.
    const canonicalHasFunds = canonicalWallets.some((wallet: Record<string, unknown>) =>
      Number(wallet.available_amount || 0) > 0 || Number(wallet.pending_amount || 0) > 0 || Number(wallet.reserved_amount || 0) > 0,
    );
    const wallets: Array<Record<string, unknown>> = [];
    // Once the corporate-profit transfer created the HQ employee wallet, it
    // is the authoritative personal balance. Do not add the old DeliGo wallet
    // on top of it, otherwise the profile shows an unrelated legacy amount.
    if (legacy?.[0] && actor.employee_code !== "DG-0001" && !canonicalHasFunds && !hqPersonalWalletHasFunds) {
      const wallet = legacy[0];
      wallets.push({
        id: wallet.id,
        platform_slug: "deligo",
        platform_name: "DeliGo",
        wallet_code: "DeliGo",
        account_type: "user",
        source_kind: "legacy",
        currency: wallet.currency,
        available_amount: Number(wallet.balance || 0),
        pending_amount: 0,
        reserved_amount: 0,
        // The migration RPC moves this legacy balance into the canonical
        // PaySuite wallet when the provider is configured. Keep the button
        // actionable so the user can start that real migration instead of
        // seeing a permanently disabled control for a valid old balance.
        withdrawal_enabled: paysuiteAvailable(),
      });
    }
    wallets.push(...visibleHqPersonalWallets);
    wallets.push(...canonicalWallets);

    // The Profile presents one personal wallet, even when the backend has
    // several platform-specific accounts. Test accounts and the founder's
    // unreconciled legacy balance have already been removed above.
    const walletComponents = wallets.slice();
    const unifiedWallet = {
      id: `personal-${walletOwnerId}`,
      platform_slug: null,
      platform_name: "Carteira pessoal",
      wallet_code: "PERSONAL_MZN",
      account_type: "user",
      source_kind: "unified_personal",
      currency: "MZN",
      available_amount: walletComponents.reduce((sum, wallet) => sum + Number(wallet.available_amount || 0), 0),
      pending_amount: walletComponents.reduce((sum, wallet) => sum + Number(wallet.pending_amount || 0), 0),
      reserved_amount: walletComponents.reduce((sum, wallet) => sum + Number(wallet.reserved_amount || 0), 0),
      withdrawal_enabled: walletComponents.some((wallet) => wallet.withdrawal_enabled === true),
    };
    wallets.splice(0, wallets.length, unifiedWallet);

    const unifiedAvailableAmount = wallets.reduce((sum, wallet) => sum + Number(wallet.available_amount || 0), 0);
    const unifiedPendingAmount = wallets.reduce((sum, wallet) => sum + Number(wallet.pending_amount || 0), 0);
    const unifiedReservedAmount = wallets.reduce((sum, wallet) => sum + Number(wallet.reserved_amount || 0), 0);
    const unifiedWithdrawableAmount = wallets
      .filter((wallet) => wallet.withdrawal_enabled === true)
      .reduce((sum, wallet) => sum + Number(wallet.available_amount || 0), 0);
    const detectedOperator = profile?.personal_phone
      ? (() => { try { return detectMozambiqueWalletOperator(String(profile.personal_phone)); } catch { return null; } })()
      : null;

    return NextResponse.json({
      profile,
      wallets,
      unified_available_amount: unifiedAvailableAmount,
      unified_pending_amount: unifiedPendingAmount,
      unified_reserved_amount: unifiedReservedAmount,
      unified_withdrawable_amount: unifiedWithdrawableAmount,
      withdrawal_phone: profile?.personal_phone || null,
      withdrawal_operator: detectedOperator?.label || null,
      withdrawal_method: detectedOperator?.method || null,
    }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    console.error("profile load failed", error);
    return NextResponse.json({ error: "Não foi possível carregar o perfil e as carteiras pessoais." }, { status: 502 });
  }
}

export async function PATCH(req: NextRequest) {
  try {
    const actor = await corporateActor();
    const key = hqServiceKey();
    if (!actor || !key) return NextResponse.json({ error: "Sessão inválida." }, { status: 401 });
    const body = await req.json() as { avatar_url?: string | null; biography?: string | null; account_preferences?: Record<string, unknown> };
    const existing = (await hqRest(`employee_display_profiles?employee_id=eq.${encodeURIComponent(actor.employee_id)}&select=*`))?.[0] || {};
    const record = {
      avatar_url: String(body.avatar_url || "").trim() || null,
      biography: String(body.biography || "").trim() || null,
      personal_phone: existing.personal_phone || null,
      alternate_contact: existing.alternate_contact || null,
      account_preferences: body.account_preferences || existing.account_preferences || {},
    };
    let profile;
    if (existing.employee_id) {
      profile = (await hqRest(`employee_display_profiles?employee_id=eq.${encodeURIComponent(actor.employee_id)}`, { method: "PATCH", body: JSON.stringify(record) }))?.[0] || null;
    } else {
      profile = (await hqRest("employee_display_profiles", { method: "POST", body: JSON.stringify({ employee_id: actor.employee_id, ...record }) }))?.[0] || null;
    }
    if (!profile) throw new Error("Perfil não foi devolvido pelo backend");
    await hqRest("audit_logs", { method: "POST", body: JSON.stringify({ actor_employee_id: actor.employee_id, action: "profile_self_service_updated", module: "profile", target_type: "employee_display_profile", target_id: actor.employee_id, result: "success", metadata: { fields: ["avatar_url", "biography", "account_preferences"], protected_fields: ["personal_phone", "alternate_contact"] } }) });
    return NextResponse.json({ profile });
  } catch (error) {
    console.error("profile update failed", error);
    return NextResponse.json({ error: "Não foi possível guardar os dados pessoais permitidos." }, { status: 409 });
  }
}
