import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization, hqRest, requireCorporatePermission } from "@/lib/hq-server";
import { platformRpc } from "@/lib/platform-backends";

const channels = new Set(["driver_reimbursed", "passenger_direct", "unknown"]);

export async function POST(request: NextRequest, { params }: { params: Promise<{ tripId: string }> }) {
  const authorization = await corporateAuthorization();
  let allowed = await requireCorporatePermission("platform.manage", "sarca", authorization || undefined);
  if (!allowed) allowed = await requireCorporatePermission("finance.manage", "sarca", authorization || undefined);
  if (!allowed) return NextResponse.json({ error: "Só Admin ou Finanças podem reconciliar uma portagem." }, { status: 403 });

  const tripId = (await params).tripId;
  if (!/^[0-9a-f-]{36}$/i.test(tripId)) return NextResponse.json({ error: "ID de viagem inválido." }, { status: 400 });
  const body = await request.json().catch(() => ({})) as Record<string, unknown>;
  const tollAmountMinor = Number(body.tollAmountMinor);
  const paymentChannel = typeof body.paymentChannel === "string" ? body.paymentChannel : "unknown";
  const source = typeof body.source === "string" ? body.source.trim().slice(0, 80) : "central";
  if (!Number.isInteger(tollAmountMinor) || tollAmountMinor < 0 || !channels.has(paymentChannel) || !source) {
    return NextResponse.json({ error: "Valor, canal de pagamento ou fonte de reconciliação inválidos." }, { status: 400 });
  }
  try {
    const result = await platformRpc("sarca", "record_trip_toll_reconciliation", {
      p_trip_id: tripId,
      p_toll_amount_minor: tollAmountMinor,
      p_payment_channel: paymentChannel,
      p_source: source,
      p_evidence: body.evidence && typeof body.evidence === "object" ? body.evidence : {},
      p_recorded_by_user_id: authorization?.actor.authUserId || null,
    });
    await hqRest("audit_logs", {
      method: "POST",
      body: JSON.stringify({ actor_employee_id: authorization?.actor.employee_id, action: "sarca_trip_toll_reconciled", module: "sarca", target_type: "trip", target_id: tripId, result: "success", metadata: { toll_amount_minor: tollAmountMinor, payment_channel: paymentChannel, source } }),
    }).catch((error) => console.error("SARCA_TOLL_AUDIT_FAILED", error));
    return NextResponse.json({ ok: true, tripId, reconciliation: result }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    console.error("SARCA_TOLL_RECONCILIATION_FAILED", error instanceof Error ? error.message : "unknown");
    return NextResponse.json({ error: "Não foi possível reconciliar a portagem desta viagem." }, { status: 409 });
  }
}
