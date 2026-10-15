import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.1";

const url = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const encoder = new TextEncoder();
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json" },
});
function hex(bytes: Uint8Array) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}
function equal(a: string, b: string) {
  const x = encoder.encode(a.toLowerCase());
  const y = encoder.encode(b.toLowerCase());
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] || 0) ^ (y[i] || 0);
  return diff === 0;
}
async function validSignature(raw: string, supplied: string, secret: string) {
  if (!secret || !supplied) return false;
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const digest = await crypto.subtle.sign("HMAC", key, encoder.encode(raw));
  return equal(hex(new Uint8Array(digest)), supplied.trim());
}
function eventData(payload: Record<string, unknown>) {
  return payload.data && typeof payload.data === "object" ? payload.data as Record<string, unknown> : payload;
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS" || req.method === "GET" || req.method === "HEAD") return new Response("OK", { status: 200 });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const raw = await req.text();
  if (!await validSignature(raw, req.headers.get("x-signature") || "", Deno.env.get("PAYSUITE_WEBHOOK_SECRET") || "")) {
    return json({ error: "invalid_signature" }, 401);
  }
  try {
    const payload = JSON.parse(raw) as Record<string, unknown>;
    const data = eventData(payload);
    const event = String(payload.event || "payment.updated").toLowerCase();
    const reference = String(data.reference || data.referencia || data.external_reference || "");
    if (!reference) return json({ ok: true, ignored: true, reason: "missing_reference" });
    const amount = Number(data.amount ?? data.valor_total ?? 0);
    const status = event.endsWith("success") || ["paid", "completed", "successful", "approved"].includes(String(data.status || "").toLowerCase()) ? "settled" : event.endsWith("failed") ? "failed" : "processing";
    const result = await admin.rpc("process_paysuite_webhook_v1", {
      p_signature: req.headers.get("x-signature"),
      p_event_type: event,
      p_external_reference: reference,
      p_amount_minor: Math.round(amount * 100),
      p_provider_reference: String(data.id || "") || null,
      p_status: status,
      p_payload: payload,
    });
    if (result.error) throw result.error;
    return json(result.data || { ok: true });
  } catch (error) {
    console.error("paysuite_webhook", error);
    return json({ error: error instanceof Error ? error.message : "invalid_webhook" }, 400);
  }
});
