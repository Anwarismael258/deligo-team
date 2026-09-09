import { NextRequest, NextResponse } from "next/server";
import { requireCorporatePermission, hqRpc } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

const actions = new Set([
  "block_client", "unblock_client", "suspend_restaurant", "reactivate_restaurant",
  "disable_courier", "reactivate_courier", "cancel_order", "resolve_incident",
  "approve_kyc", "reject_kyc",
]);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function POST(request: NextRequest) {
  const authorization = await requireCorporatePermission("platform.manage", "deligo");
  if (!authorization) return NextResponse.json({ error: "Sem permissão para administrar a DeliGo." }, { status: 403 });
  const body = await request.json().catch(() => ({})) as { action?: string; entityId?: string; reason?: string; sessionId?: string };
  const action = String(body.action || "").trim().toLowerCase();
  const entityId = String(body.entityId || "").trim();
  const reason = String(body.reason || "").trim();
  if (!actions.has(action) || !uuid.test(entityId)) return NextResponse.json({ error: "Ação ou entidade inválida." }, { status: 400 });
  if (reason.length < 6) return NextResponse.json({ error: "Indique um motivo com pelo menos 6 caracteres." }, { status: 400 });
  try {
    const result = await hqRpc("hq_deligo_admin_command_v1", {
      p_actor_auth_user_id: authorization.actor.authUserId,
      p_action: action,
      p_entity_id: entityId,
      p_reason: reason,
      p_session_metadata: {
        session_id: body.sessionId || null,
        user_agent: request.headers.get("user-agent"),
        forwarded_for: request.headers.get("x-forwarded-for"),
        employee_id: authorization.actor.employee_id,
      },
    });
    return NextResponse.json({ result });
  } catch (error) {
    const detail = error instanceof Error ? error.message : "COMMAND_FAILED";
    const known = detail.match(/(not_found|not_cancellable|administrative_reason_required)/i);
    return NextResponse.json({ error: known ? detail : "A decisão não pôde ser aplicada." }, { status: 409 });
  }
}
