import { NextResponse } from "next/server";
import { corporateActor, hqRpc } from "@/lib/hq-server";

export async function GET() {
  const actor = await corporateActor();
  if (!actor || !["SUPER_ADMIN","HUMAN_RESOURCES"].includes(actor.role)) return NextResponse.json({ error: "Sem acesso à auditoria." }, { status: 403 });
  return NextResponse.json({ events: await hqRpc("hq_audit_history_v1", { p_limit: actor.role === "SUPER_ADMIN" ? 250 : 100 }) }, { headers: { "Cache-Control": "private, no-store" } });
}
