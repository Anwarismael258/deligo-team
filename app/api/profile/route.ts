import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRest, hqServiceKey, stagingRest, supabaseUrl } from "@/lib/hq-server";

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
    withdrawal_enabled: metadata.withdrawal_disabled !== true && metadata.provider_integration === "paysuite",
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
    const profileRows = await hqRest(`employee_display_profiles?employee_id=eq.${encodeURIComponent(actor.employee_id)}&select=*`);
    // A login token can belong to a legacy Auth identity while the employee
    // record already points to the canonical identity used by DeliGo's
    // personal wallet. Resolve the wallet owner from the employee record so
    // the profile never displays an unrelated zero-balance legacy wallet.
    const employeeRows = await hqRest(`employees?id=eq.${encodeURIComponent(actor.employee_id)}&select=auth_user_id`);
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
      withdrawal_enabled: false,
    }));
    const hqPersonalWalletHasFunds = hqPersonalWallets.some((wallet) =>
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
    if (legacy?.[0] && !canonicalHasFunds && !hqPersonalWalletHasFunds) {
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
        withdrawal_enabled: process.env.PAYSUITE_ENABLED === "true" && Boolean(process.env.PAYSUITE_API_TOKEN),
      });
    }
    wallets.push(...hqPersonalWallets);
    wallets.push(...canonicalWallets);

    const unifiedAvailableAmount = wallets.reduce((sum, wallet) => sum + Number(wallet.available_amount || 0), 0);
    const unifiedPendingAmount = wallets.reduce((sum, wallet) => sum + Number(wallet.pending_amount || 0), 0);
    const unifiedReservedAmount = wallets.reduce((sum, wallet) => sum + Number(wallet.reserved_amount || 0), 0);
    const unifiedWithdrawableAmount = wallets
      .filter((wallet) => wallet.withdrawal_enabled === true)
      .reduce((sum, wallet) => sum + Number(wallet.available_amount || 0), 0);

    return NextResponse.json({
      profile,
      wallets,
      unified_available_amount: unifiedAvailableAmount,
      unified_pending_amount: unifiedPendingAmount,
      unified_reserved_amount: unifiedReservedAmount,
      unified_withdrawable_amount: unifiedWithdrawableAmount,
      withdrawal_phone: profile?.personal_phone || null,
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
