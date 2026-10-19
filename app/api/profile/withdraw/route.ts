import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRest, hqRpc, supabaseUrl } from "@/lib/hq-server";
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
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw new Error("SUPABASE_SERVICE_ROLE_NOT_CONFIGURED");
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json", Prefer: "return=representation", "Content-Profile": "payments", "Accept-Profile": "payments", ...(init.headers || {}) },
    cache: "no-store",
  });
  if (!response.ok) throw new Error((await response.text()) || "PAYMENTS_REST_FAILED");
  return response.status === 204 ? null : response.json();
}

export async function POST(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor) return NextResponse.json({ error: "Sessão inválida." }, { status: 401 });
  const body = await request.json().catch(() => null) as { walletId?: string; amount?: number; method?: string } | null;
  const amount = Number(body?.amount);
  if (!Number.isFinite(amount) || amount <= 0) return NextResponse.json({ error: "Indique um valor válido." }, { status: 400 });
  if (!body?.walletId || !["mpesa", "emola"].includes(String(body.method))) return NextResponse.json({ error: "Carteira e método são obrigatórios." }, { status: 400 });
  if (process.env.PAYSUITE_ENABLED !== "true" || !process.env.PAYSUITE_API_TOKEN) return NextResponse.json({ error: "PaySuite ainda não está activa para levantamentos reais." }, { status: 503 });
  try {
    const employeeProfiles = await hqRest(`employee_display_profiles?employee_id=eq.${encodeURIComponent(actor.employee_id)}&select=personal_phone` ) as Array<{ personal_phone?: string | null }>;
    const phone = normalizePhone(String(employeeProfiles?.[0]?.personal_phone || ""));
    const wallets = await paymentsRest(`wallet_accounts?id=eq.${encodeURIComponent(body.walletId)}&owner_user_id=eq.${encodeURIComponent(actor.authUserId)}&account_type=eq.user&status=eq.active&select=*`) as Array<Record<string, unknown>>;
    const wallet = wallets?.[0];
    if (!wallet) return NextResponse.json({ error: "Carteira pessoal não encontrada." }, { status: 404 });
    const metadata = (wallet.metadata && typeof wallet.metadata === "object" ? wallet.metadata : {}) as Record<string, unknown>;
    if (metadata.withdrawal_disabled === true || metadata.provider_integration !== "paysuite") return NextResponse.json({ error: "Esta carteira ainda não foi activada para PaySuite." }, { status: 409 });
    const availableMinor = Number(wallet.available_balance_minor || 0);
    const requestedMinor = moneyMinor(amount);
    if (requestedMinor > availableMinor) return NextResponse.json({ error: "Saldo disponível insuficiente." }, { status: 409 });
    const feeMinor = Math.round(requestedMinor * 0.03);
    const netMinor = requestedMinor - feeMinor;
    if (netMinor <= 0) return NextResponse.json({ error: "O valor líquido após a taxa PaySuite deve ser positivo." }, { status: 400 });
    const idempotencyKey = `employee-payout-${actor.authUserId}-${crypto.randomUUID()}`;
    const reference = `DLGWD${crypto.randomUUID().replace(/-/g, "").slice(0, 20).toUpperCase()}`;
    const [payout] = await paymentsRest("payout_requests", { method: "POST", body: JSON.stringify({ app_id: APP_ID, source_wallet_account_id: wallet.id, beneficiary_user_id: actor.authUserId, requested_by: actor.authUserId, amount_minor: requestedMinor, fee_minor: feeMinor, status: "pending", destination_phone: phone, method: body.method, idempotency_key: idempotencyKey, request_note: "Levantamento pessoal iniciado no perfil", metadata: { reference, provider: "paysuite", employee_id: actor.employee_id, gross_amount_minor: requestedMinor, net_amount_minor: netMinor } }) }) as Array<Record<string, unknown>>;
    if (!payout?.id) throw new Error("PAYOUT_REQUEST_NOT_CREATED");
    await hqRpc("reserve_paysuite_payout_v1", { p_payout_request_id: payout.id });
    let provider: Record<string, unknown>;
    try {
      provider = await paysuiteRequest<Record<string, unknown>>("/payouts", { method: "POST", body: JSON.stringify({ amount: (netMinor / 100).toFixed(2), currency: "MZN", reference, description: `Levantamento DeliGo Team - ${actor.name}`, beneficiary: { phone, holder: actor.name }, method: body.method, webhook_url: `${supabaseUrl()}/api/payments/paysuite/webhook` }) });
    } catch (error) {
      await hqRpc("fail_paysuite_payout_v1", { p_payout_request_id: payout.id, p_reason: error instanceof Error ? error.message : "PaySuite indisponível" });
      return NextResponse.json({ error: "PaySuite não aceitou o pedido; o saldo reservado foi libertado." }, { status: 502 });
    }
    const providerStatus = String(provider.status || provider.state || "pending").toLowerCase();
    const providerReference = String(provider.id || provider.reference || reference);
    if (["success", "successful", "completed", "complete", "paid"].includes(providerStatus)) {
      await hqRpc("complete_paysuite_payout_v1", { p_payout_request_id: payout.id, p_provider_reference: providerReference });
      await hqRest("audit_logs", { method: "POST", body: JSON.stringify({ actor_employee_id: actor.employee_id, action: "employee_paysuite_withdrawal_completed", module: "profile", target_type: "payout_request", target_id: payout.id, result: "success", metadata: { provider_reference: providerReference, amount_minor: requestedMinor } }) });
      return NextResponse.json({ status: "paid", payoutId: payout.id, providerReference });
    }
    return NextResponse.json({ status: "processing", payoutId: payout.id, providerReference }, { status: 202 });
  } catch (error) {
    console.error("employee_paysuite_withdrawal_failed", error);
    return NextResponse.json({ error: "Não foi possível iniciar o levantamento. Nenhuma transferência foi confirmada." }, { status: 409 });
  }
}
