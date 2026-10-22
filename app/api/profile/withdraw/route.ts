import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRest, hqRpc, hqServiceKey, supabaseUrl } from "@/lib/hq-server";
import { paysuiteRequest } from "@/lib/paysuite";

const APP_ID = "7628e590-652b-4e93-9ff0-d258e351303c";
const moneyMinor = (value: number) => Math.round(value * 100);
const normalizePhone = (value: string) => {
  const digits = value.replace(/\D/g, "");
  const local = digits.startsWith("258") ? digits.slice(3) : digits;
  if (!/^(82|83|84|85|86|87)\d{7}$/.test(local)) throw new Error("Número PaySuite inválido.");
  return local;
};

async function paymentsRest(path: string, init: RequestInit = {}) {
  const key = hqServiceKey();
  if (!key) throw new Error("SUPABASE_SERVICE_ROLE_NOT_CONFIGURED");
  const privileged = key.startsWith("sb_secret_") ? { apikey: key } : { apikey: key, Authorization: `Bearer ${key}` };
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, {
    ...init,
    headers: {
      ...privileged,
      "Content-Type": "application/json",
      Prefer: "return=representation",
      "Content-Profile": "payments",
      "Accept-Profile": "payments",
      ...(init.headers || {}),
    },
    cache: "no-store",
  });
  if (!response.ok) throw new Error((await response.text()) || "PAYMENTS_REST_FAILED");
  return response.status === 204 ? null : response.json();
}

type Wallet = Record<string, unknown> & { id: string; available_balance_minor: number; metadata: Record<string, unknown> };
type PreparedPayout = { payout: Record<string, unknown>; wallet: Wallet; amountMinor: number; netMinor: number; reference: string; reserved: boolean };
const PAYSUITE_FEE_RATE = 0.03;

function isPaySuiteWallet(wallet: Record<string, unknown>) {
  const metadata = (wallet.metadata && typeof wallet.metadata === "object" ? wallet.metadata : {}) as Record<string, unknown>;
  return metadata.withdrawal_disabled !== true && metadata.provider_integration === "paysuite";
}

export async function POST(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor) return NextResponse.json({ error: "Sessão inválida." }, { status: 401 });

  const body = await request.json().catch(() => null) as { walletId?: string; amount?: number; method?: string } | null;
  const amount = Number(body?.amount);
  const method = body?.method == null ? "mpesa" : String(body.method);
  if (!Number.isFinite(amount) || amount <= 0) return NextResponse.json({ error: "Indique um valor válido." }, { status: 400 });
  if (!["mpesa", "emola"].includes(method)) return NextResponse.json({ error: "Método de levantamento inválido." }, { status: 400 });
  if (process.env.PAYSUITE_ENABLED !== "true" || !process.env.PAYSUITE_API_TOKEN) return NextResponse.json({ error: "PaySuite ainda não está activa para levantamentos reais." }, { status: 503 });

  try {
    const employeeProfiles = await hqRest(`employee_display_profiles?employee_id=eq.${encodeURIComponent(actor.employee_id)}&select=personal_phone`) as Array<{ personal_phone?: string | null }>;
    const phone = normalizePhone(String(employeeProfiles?.[0]?.personal_phone || ""));
    // The profile API can still show a real legacy DeliGo personal balance
    // while the PaySuite account is empty. Reconcile only this authenticated
    // worker's wallet, never corporate or unattributed payment aggregates.
    await hqRpc("migrate_legacy_personal_wallet_to_paysuite_v1", { p_auth_user_id: actor.authUserId }).catch((error) => {
      console.warn("legacy_personal_wallet_migration_skipped", error);
    });
    const walletFilter = body?.walletId
      ? `id=eq.${encodeURIComponent(body.walletId)}&owner_user_id=eq.${encodeURIComponent(actor.authUserId)}`
      : `owner_user_id=eq.${encodeURIComponent(actor.authUserId)}`;
    // Consolidate every personal wallet owned by this worker. Corporate
    // wallets have no owner_user_id and are never included here.
    const wallets = await paymentsRest(`wallet_accounts?${walletFilter}&status=eq.active&currency_code=eq.MZN&select=*`) as Wallet[];
    const eligibleWallets = (Array.isArray(wallets) ? wallets : []).filter(isPaySuiteWallet).filter((wallet) => Number(wallet.available_balance_minor || 0) > 0);
    const totalAvailableMinor = eligibleWallets.reduce((sum, wallet) => sum + Number(wallet.available_balance_minor || 0), 0);
    const requestedMinor = moneyMinor(amount);
    if (!eligibleWallets.length) return NextResponse.json({ error: "Nenhuma carteira pessoal está activa para levantamento PaySuite. A carteira corporativa não entra neste botão." }, { status: 409 });
    if (requestedMinor > totalAvailableMinor) return NextResponse.json({ error: "Saldo pessoal disponível insuficiente." }, { status: 409 });

    let remainingMinor = requestedMinor;
    const allocations = eligibleWallets.map((wallet) => {
      const amountMinor = Math.min(Number(wallet.available_balance_minor || 0), remainingMinor);
      remainingMinor -= amountMinor;
      return { wallet, amountMinor };
    }).filter((allocation) => allocation.amountMinor > 0);
    const prepared: PreparedPayout[] = [];

    try {
      for (const allocation of allocations) {
        const feeMinor = Math.round(allocation.amountMinor * PAYSUITE_FEE_RATE);
        const netMinor = allocation.amountMinor - feeMinor;
        if (netMinor <= 0) throw new Error("O valor líquido após a taxa PaySuite deve ser positivo.");
        const idempotencyKey = `employee-payout-${actor.authUserId}-${crypto.randomUUID()}`;
        const reference = `DLGWD${crypto.randomUUID().replace(/-/g, "").slice(0, 20).toUpperCase()}`;
        const [payout] = await paymentsRest("payout_requests", {
          method: "POST",
          body: JSON.stringify({
            app_id: APP_ID,
            source_wallet_account_id: allocation.wallet.id,
            beneficiary_user_id: actor.authUserId,
            requested_by: actor.authUserId,
            amount_minor: allocation.amountMinor,
            fee_minor: feeMinor,
            status: "pending",
            destination_phone: phone,
            method,
            idempotency_key: idempotencyKey,
            request_note: "Levantamento pessoal unificado no perfil",
            metadata: { reference, provider: "paysuite", employee_id: actor.employee_id, gross_amount_minor: allocation.amountMinor, net_amount_minor: netMinor, unified_withdrawal: true },
          }),
        }) as Array<Record<string, unknown>>;
        if (!payout?.id) throw new Error("PAYOUT_REQUEST_NOT_CREATED");
        const item: PreparedPayout = { payout, wallet: allocation.wallet, amountMinor: allocation.amountMinor, netMinor, reference, reserved: false };
        prepared.push(item);
        await hqRpc("reserve_paysuite_payout_v1", { p_payout_request_id: payout.id });
        item.reserved = true;
      }
    } catch (error) {
      for (const item of prepared) {
        if (item.reserved) {
          await hqRpc("fail_paysuite_payout_v1", { p_payout_request_id: item.payout.id, p_reason: "Levantamento unificado não pôde ser preparado integralmente." }).catch(() => undefined);
        } else {
          await paymentsRest(`payout_requests?id=eq.${encodeURIComponent(String(item.payout.id))}`, { method: "PATCH", body: JSON.stringify({ status: "failed", rejection_reason: "Levantamento unificado não pôde ser preparado integralmente." }) }).catch(() => undefined);
        }
      }
      throw error;
    }

    const results: Array<{ payoutId: unknown; status: string; providerReference?: string }> = [];
    for (const item of prepared) {
      try {
        const provider = await paysuiteRequest<Record<string, unknown>>("/payouts", {
          method: "POST",
          body: JSON.stringify({ amount: (item.netMinor / 100).toFixed(2), currency: "MZN", reference: item.reference, description: `Levantamento DeliGo Team - ${actor.name}`, beneficiary: { phone, holder: actor.name }, method, webhook_url: `${supabaseUrl()}/api/payments/paysuite/webhook` }),
        });
        const providerStatus = String(provider.status || provider.state || "pending").toLowerCase();
        const providerReference = String(provider.id || provider.reference || item.reference);
        if (["success", "successful", "completed", "complete", "paid"].includes(providerStatus)) {
          await hqRpc("complete_paysuite_payout_v1", { p_payout_request_id: item.payout.id, p_provider_reference: providerReference });
          await hqRest("audit_logs", { method: "POST", body: JSON.stringify({ actor_employee_id: actor.employee_id, action: "employee_paysuite_withdrawal_completed", module: "profile", target_type: "payout_request", target_id: item.payout.id, result: "success", metadata: { provider_reference: providerReference, amount_minor: item.amountMinor, unified_withdrawal: true } }) });
          results.push({ payoutId: item.payout.id, status: "paid", providerReference });
        } else {
          results.push({ payoutId: item.payout.id, status: "processing", providerReference });
        }
      } catch (error) {
        await hqRpc("fail_paysuite_payout_v1", { p_payout_request_id: item.payout.id, p_reason: error instanceof Error ? error.message : "PaySuite indisponível" }).catch(() => undefined);
        results.push({ payoutId: item.payout.id, status: "failed" });
      }
    }

    const hasFailed = results.some((result) => result.status === "failed");
    const allPaid = results.every((result) => result.status === "paid");
    const status = allPaid ? "paid" : hasFailed ? "partial" : "processing";
    return NextResponse.json({ status, payoutId: results[0]?.payoutId, payoutIds: results.map((result) => result.payoutId), providerReference: results[0]?.providerReference, providerReferences: results.map((result) => result.providerReference).filter(Boolean), results }, { status: hasFailed ? 502 : allPaid ? 200 : 202 });
  } catch (error) {
    console.error("employee_paysuite_withdrawal_failed", error);
    return NextResponse.json({ error: "Não foi possível iniciar o levantamento. Nenhuma transferência foi confirmada." }, { status: 409 });
  }
}
