import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { corporateActor, hqRest } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

function normalizeMozPhone(value: unknown) {
  const digits = String(value || "").replace(/\D/g, "");
  if (/^2588\d{8}$/.test(digits)) return `+${digits}`;
  if (/^8\d{8}$/.test(digits)) return `+258${digits}`;
  return String(value || "").trim();
}

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
    const [employees, profiles] = await Promise.all([
      hqRest(`employees?id=eq.${encodeURIComponent(actor.employee_id)}&select=phone_e164`) as Promise<Array<{ phone_e164?: string | null }>>,
      hqRest(`employee_display_profiles?employee_id=eq.${encodeURIComponent(actor.employee_id)}&select=personal_phone`) as Promise<Array<{ personal_phone?: string | null }>>,
    ]);
    const phone = normalizeMozPhone(employees?.[0]?.phone_e164 || profiles?.[0]?.personal_phone);
    if (!/^\+258\d{9}$/.test(phone)) return NextResponse.json({ error: "O número de levantamento registado para este perfil não é válido." }, { status: 409 });
    const prepared = await authenticatedRpc("hq_prepare_corporate_withdrawal_v1", { p_amount: amount, p_method: "mpesa", p_phone_number: phone, p_idempotency_key: String(body?.idempotencyKey || `hq-${actor.employee_id}-${Date.now()}`).trim() });
    const withdrawalId = String((prepared as Record<string, unknown>).withdrawal_id || "");
    if (!withdrawalId) return NextResponse.json({ error: "Pedido financeiro sem identificador." }, { status: 502 });
    const otp = await authenticatedRpc("hq_send_corporate_withdrawal_otp_v1", { p_withdrawal_id: withdrawalId });
    return NextResponse.json({ prepared, otp });
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "Não foi possível processar o pedido." }, { status: 409 }); }
}
