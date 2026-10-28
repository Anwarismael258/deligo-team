import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { corporateActor, hqRpc } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

async function authenticatedRpc(name: string, body: Record<string, unknown>) {
  const token = (await cookies()).get("hq_access_token")?.value;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  const url = process.env.SUPABASE_URL?.trim().replace(/\/$/, "");
  if (!token || !anonKey || !url) throw new Error("authentication_required");
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: anonKey, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    cache: "no-store",
  });
  if (!response.ok) throw new Error((await response.text()) || "HQ_RPC_FAILED");
  return response.json();
}

export async function POST(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor || !["SUPER_ADMIN", "FINANCE"].includes(actor.role)) return NextResponse.json({ error: "Apenas Admin ou Finanças podem iniciar este pedido." }, { status: 403 });
  const body = await request.json().catch(() => null) as { amount?: number; method?: string; phoneNumber?: string; idempotencyKey?: string; otp?: string; withdrawalId?: string } | null;
  try {
    if (body?.withdrawalId && body.otp) {
      const confirmed = await authenticatedRpc("hq_confirm_corporate_withdrawal_v1", { p_withdrawal_id: body.withdrawalId, p_otp: body.otp });
      const transferred = await authenticatedRpc("hq_transfer_approved_profit_v1", { p_withdrawal_id: body.withdrawalId });
      return NextResponse.json({ confirmed, transferred });
    }
    if (body?.withdrawalId) {
      const otp = await authenticatedRpc("hq_send_corporate_withdrawal_otp_v1", { p_withdrawal_id: body.withdrawalId });
      return NextResponse.json({ otp, resent: true });
    }
    const amount = Number(body?.amount);
    if (!Number.isFinite(amount) || amount <= 0) return NextResponse.json({ error: "Informe um valor válido." }, { status: 400 });
    const rawFinanceSummary = await hqRpc("hq_deligo_finance_summary_v1", {
      p_actor_auth_user_id: actor.authUserId,
      p_from: null,
      p_to: null,
    }) as Record<string, unknown>;
    // The finance RPC returns the canonical values under `summary` and the
    // platform reconciliation under `breakdown`. Older responses were flat;
    // support both shapes so a valid confirmed balance is never read as 0.
    const financeSummary = rawFinanceSummary.summary && typeof rawFinanceSummary.summary === "object"
      ? rawFinanceSummary.summary as Record<string, unknown>
      : rawFinanceSummary;
    const financeBreakdown = rawFinanceSummary.breakdown && typeof rawFinanceSummary.breakdown === "object"
      ? rawFinanceSummary.breakdown as Record<string, unknown>
      : {};
    const confirmedRevenue = Number(financeSummary.corporate_revenue_confirmed ?? financeBreakdown.central_revenue_confirmed ?? 0);
    const reportedWithdrawable = Number(financeSummary.corporate_profit_withdrawable);
    const pendingWithdrawals = Number(financeSummary.corporate_pending_withdrawals ?? 0);
    // During the transition between the legacy and canonical summaries the
    // profit field can be absent/zero while the confirmed revenue is present.
    // Use the confirmed revenue minus already-pending requests only in that
    // explicit mismatch; the approval RPC remains the final balance check.
    const profitComponents = Number(financeSummary.deligo_profit ?? 0) + Number(financeSummary.mestre24_profit ?? 0);
    const withdrawableRevenue = Number.isFinite(reportedWithdrawable) && reportedWithdrawable > 0
      ? reportedWithdrawable
      : profitComponents <= 0 && confirmedRevenue > 0
        ? Math.max(confirmedRevenue - pendingWithdrawals, 0)
        : 0;
    if (!Number.isFinite(withdrawableRevenue) || amount > withdrawableRevenue) {
      return NextResponse.json({
        error: `O valor ultrapassa a receita corporativa confirmada disponível (${withdrawableRevenue.toFixed(2)} MZN).`,
        availableAmount: withdrawableRevenue,
      }, { status: 409 });
    }
    // This is an internal ledger transfer, not a PaySuite payout. The
    // approved RPC moves CORPORATE_MZN -> the requesting employee wallet;
    // only the separate profile withdrawal may call PaySuite later.
    const prepared = await authenticatedRpc("hq_prepare_corporate_withdrawal_v1", {
      p_amount: amount,
      p_method: "internal_transfer",
      p_phone_number: "HQ_INTERNAL_WALLET",
      p_idempotency_key: String(body?.idempotencyKey || `hq-${actor.employee_id}-${Date.now()}`).trim(),
    });
    const withdrawalId = String((prepared as Record<string, unknown>).withdrawal_id || "");
    if (!withdrawalId) return NextResponse.json({ error: "Pedido financeiro sem identificador." }, { status: 502 });
    const otp = await authenticatedRpc("hq_send_corporate_withdrawal_otp_v1", { p_withdrawal_id: withdrawalId });
    return NextResponse.json({ prepared, otp });
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "Não foi possível processar o pedido." }, { status: 409 }); }
}
