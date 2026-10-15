import { hqRpc } from "@/lib/hq-server";
export async function auditDilEvent(event: Record<string, unknown>) {
  try { await hqRpc("hq_ai_audit_event_v1", { p_event: event }); return "persisted" as const; }
  catch (error) { console.error("DIL_AUDIT_PERSIST_FAILED", { event, error: String(error) }); return "fallback_log" as const; }
}
