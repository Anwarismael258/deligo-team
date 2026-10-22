import { NextRequest, NextResponse } from "next/server";
import { dispatchMicrocreditPacket } from "@/lib/microcredit-packets";
import { stagingRest } from "@/lib/hq-server";

export async function GET(request: NextRequest) {
  const expected = process.env.CRON_SECRET?.trim();
  const supplied = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") || request.headers.get("x-cron-secret");
  if (!expected) return NextResponse.json({ error: "CRON_SECRET não configurado." }, { status: 503 });
  if (!supplied || supplied !== expected) return NextResponse.json({ error: "Não autorizado." }, { status: 401 });
  try {
    const rows = await stagingRest("loan_applications?status=eq.pendente&select=*&order=created_at.asc&limit=50") as Array<Record<string, unknown>>;
    const results = [];
    for (const application of rows || []) {
      try { results.push({ id: application.id, ...(await dispatchMicrocreditPacket(application, "submitted")) }); }
      catch (error) { results.push({ id: application.id, error: error instanceof Error ? error.message.split(":")[0] : "MICROCREDIT_DISPATCH_FAILED" }); }
    }
    return NextResponse.json({ ok: true, processed: results });
  } catch {
    return NextResponse.json({ error: "Não foi possível processar os pedidos de microcrédito." }, { status: 502 });
  }
}
