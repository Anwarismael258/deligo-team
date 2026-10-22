import { NextRequest, NextResponse } from "next/server";
import { stagingRest } from "@/lib/hq-server";
import { dispatchMicrocreditPacket, microcreditDispatchSecretMatches } from "@/lib/microcredit-packets";

export async function POST(request: NextRequest) {
  if (!microcreditDispatchSecretMatches(request.headers.get("x-microcredit-secret"))) return NextResponse.json({ error: "Despacho não autorizado." }, { status: 401 });
  const body = await request.json().catch(() => ({})) as { application_id?: string; kind?: "submitted" | "confirmed" };
  if (!body.application_id || !body.kind || !["submitted", "confirmed"].includes(body.kind)) return NextResponse.json({ error: "Pedido de despacho inválido." }, { status: 400 });
  try {
    const rows = await stagingRest(`loan_applications?id=eq.${encodeURIComponent(body.application_id)}&limit=1`) as Array<Record<string, unknown>>;
    const application = rows?.[0];
    if (!application) return NextResponse.json({ error: "Pedido não encontrado." }, { status: 404 });
    const result = await dispatchMicrocreditPacket(application, body.kind);
    return NextResponse.json({ ok: true, ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "MICROCREDIT_DISPATCH_FAILED";
    const status = message.includes("NOT_CONFIGURED") ? 503 : 502;
    return NextResponse.json({ error: "Não foi possível entregar o PDF pelo WhatsApp.", code: message.split(":")[0] }, { status });
  }
}
