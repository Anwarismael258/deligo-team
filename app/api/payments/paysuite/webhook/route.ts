import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";

function validSignature(raw: string, signature: string) {
  const secret = process.env.PAYSUITE_WEBHOOK_SECRET;
  if (!secret || !signature) return false;
  const expected = createHmac("sha256", secret).update(raw).digest("hex");
  const a = Buffer.from(expected, "utf8");
  const b = Buffer.from(signature, "utf8");
  return a.length === b.length && timingSafeEqual(a, b);
}

export async function POST(request: NextRequest) {
  const raw = await request.text();
  if (!validSignature(raw, request.headers.get("x-signature") || "")) {
    return NextResponse.json({ error: "Assinatura PaySuite inválida." }, { status: 401 });
  }
  let event: { event?: string; data?: { id?: string; status?: string; reference?: string } };
  try { event = JSON.parse(raw); } catch { return NextResponse.json({ error: "Payload inválido." }, { status: 400 }); }
  const supported = ["payment.success", "payment.failed", "payout.success", "payout.failed", "refund.success", "refund.failed"];
  if (!event.event || !supported.includes(event.event)) return NextResponse.json({ received: true, ignored: true });
  const providerId = event.data?.id;
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!providerId || !url || !key) return NextResponse.json({ error: "Inbox PaySuite não configurada." }, { status: 503 });
  const payloadHash = createHash("sha256").update(raw).digest("hex");
  const response = await fetch(`${url}/rest/v1/provider_webhook_events`, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json", "Content-Profile": "payments", Prefer: "resolution=ignore-duplicates,return=minimal" },
    body: JSON.stringify({ provider: "paysuite", signature: request.headers.get("x-signature"), provider_event_type: event.event, external_reference: event.data?.reference || null, payload: event })
  });
  if (!response.ok) return NextResponse.json({ error: "Não foi possível registar o evento PaySuite." }, { status: 503 });
  const data = event.data as (Record<string, unknown> | undefined);
  const amountMinor = Number(data?.amount_minor ?? data?.amountMinor ?? data?.amount ?? 0);
  const rpc = await fetch(`${url}/rest/v1/rpc/process_paysuite_webhook_v1`, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_signature: request.headers.get("x-signature"), p_event_type: event.event, p_external_reference: data?.reference || null, p_amount_minor: amountMinor, p_provider_reference: data?.id || null, p_status: data?.status || (event.event === "payment.success" ? "settled" : event.event === "payment.failed" ? "failed" : event.event), p_payload: event })
  });
  if (!rpc.ok) return NextResponse.json({ error: "Evento recebido, mas o settlement financeiro falhou." }, { status: 503 });
  return NextResponse.json({ received: true, event: event.event, provider_id: providerId, settlement: await rpc.json().catch(() => null) });
}
