import { NextResponse } from "next/server";
import { corporateActor, hqRpc } from "@/lib/hq-server";

type AuditEvent = {
  occurred_at: string;
  actor: string;
  action: string;
  module: string;
  target_type: string;
  target_id: string | null;
  result: string;
  ip_address: string | null;
};

const csvCell = (value: unknown) => `"${String(value ?? "").replaceAll('"', '""')}"`;

export async function GET() {
  const actor = await corporateActor();
  if (!actor || !["SUPER_ADMIN", "HUMAN_RESOURCES"].includes(actor.role)) {
    return NextResponse.json({ error: "Sem acesso Ã exportação de auditoria." }, { status: 403 });
  }

  const events = await hqRpc("hq_audit_history_v1", { p_limit: actor.role === "SUPER_ADMIN" ? 500 : 100 }) as AuditEvent[];
  await hqRpc("hq_log_audit_export_v1", { p_actor_auth_user_id: actor.authUserId, p_export_kind: "audit_csv", p_record_count: events.length });
  const csv = [
    ["data", "actor", "acção", "módulo", "tipo de alvo", "id do alvo", "resultado", "ip"],
    ...events.map((event) => [event.occurred_at, event.actor, event.action, event.module, event.target_type, event.target_id, event.result, event.ip_address]),
  ].map((row) => row.map(csvCell).join(",")).join("\r\n");

  return new NextResponse(`\uFEFF${csv}`, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="deligo-auditoria-${new Date().toISOString().slice(0, 10)}.csv"`,
      "Cache-Control": "private, no-store",
    },
  });
}
