import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRest, hqRpc } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor || !["SUPER_ADMIN", "FINANCE"].includes(actor.role)) return NextResponse.json({ error: "Apenas Admin ou Finanças podem iniciar este pedido." }, { status: 403 });
  const body = await request.json().catch(() => null) as { amount?: number; method?: string; phoneNumber?: string; idempotencyKey?: string; otp?: string; withdrawalId?: string } | null;
  try {
    if (body?.withdrawalId && body.otp) {
      const confirmed = await hqRpc("hq_confirm_corporate_withdrawal_v1", { p_withdrawal_id: body.withdrawalId, p_otp: body.otp });
      const transferred = await hqRpc("hq_transfer_approved_profit_v1", { p_withdrawal_id: body.withdrawalId });
      return NextResponse.json({ confirmed, transferred });
    }
    const amount = Number(body?.amount);
    if (!Number.isFinite(amount) || amount <= 0) return NextResponse.json({ error: "Informe um valor válido." }, { status: 400 });
    const profiles = await hqRest(`employee_display_profiles?employee_id=eq.${encodeURIComponent(actor.employee_id)}&select=personal_phone`) as Array<{ personal_phone?: string | null }>;
    const phone = String(profiles?.[0]?.personal_phone || "").trim();
    if (!/^\+258\d{9}$/.test(phone)) return NextResponse.json({ error: "O número de levantamento registado para este perfil não é válido." }, { status: 409 });
    const prepared = await hqRpc("hq_prepare_corporate_withdrawal_v1", { p_amount: amount, p_method: "mpesa", p_phone_number: phone, p_idempotency_key: String(body?.idempotencyKey || `hq-${actor.employee_id}-${Date.now()}`).trim() });
    const withdrawalId = String((prepared as Record<string, unknown>).withdrawal_id || "");
    if (!withdrawalId) return NextResponse.json({ error: "Pedido financeiro sem identificador." }, { status: 502 });
    const otp = await hqRpc("hq_send_corporate_withdrawal_otp_v1", { p_withdrawal_id: withdrawalId });
    return NextResponse.json({ prepared, otp });
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "Não foi possível processar o pedido." }, { status: 409 }); }
}
