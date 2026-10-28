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
  const text=await response.text();
  return text.trim()?JSON.parse(text):null;
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
    const availability=await hqRpc("corporate_revenue_availability_v1",{},"hq") as Record<string,unknown>;
    if(availability.corporate_profit_withdrawable==null)throw new Error("Receita disponível temporariamente indisponível.");
    const withdrawableRevenue=Number(availability.corporate_profit_withdrawable);
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
      p_idempotency_key: String(body?.idempotencyKey || `hq-${actor.employee_id}-${crypto.randomUUID()}`).trim(),
    });
    const withdrawalId = String((prepared as Record<string, unknown>).withdrawal_id || "");
    if (!withdrawalId) return NextResponse.json({ error: "Pedido financeiro sem identificador." }, { status: 502 });
    const otp = await authenticatedRpc("hq_send_corporate_withdrawal_otp_v1", { p_withdrawal_id: withdrawalId });
    return NextResponse.json({ prepared, otp });
  } catch (error) {
    const message = error instanceof Error ? error.message : "";
    if (/platform_admin_required|42501/i.test(message)) {
      return NextResponse.json({ error: "O fluxo de dupla aprovação da receita ainda está protegido pela política antiga do Supabase. É necessário publicar a função de preparação para aceitar CEO/Finanças; o saldo não foi alterado." }, { status: 503 });
    }
    return NextResponse.json({ error: message || "Não foi possível processar o pedido." }, { status: 409 });
  }
}
