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
function paysuiteProviderFee(data: Record<string, unknown>, grossAmount: number) {
  const explicit = [data.provider_fee, data.providerFee, data.fee, data.taxa, data.transaction_fee, data.transactionFee]
    .map(value => Number(value))
    .find(value => Number.isFinite(value) && value >= 0 && value <= grossAmount);
  return Number((explicit ?? grossAmount * 0.03).toFixed(2));
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

    // Mestre24 subscriptions are not wallet deposits. Settle the cycle and
    // profile directly so a successful PaySuite checkout unlocks the account.
    const { data: cycle } = await admin
      .schema("mestre24")
      .from("subscription_cycles")
      .select("id, professional_user_id, amount, status, provider")
      .eq("provider_reference", reference)
      .maybeSingle();
    if (cycle) {
      if (status === "settled") {
        const startsAt = new Date().toISOString();
        const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
        const { error: cycleError } = await admin
          .schema("mestre24")
          .from("subscription_cycles")
          .update({
            status: "active",
            starts_at: startsAt,
            expires_at: expiresAt,
            paid_at: startsAt,
            provider_reference: reference,
          })
          .eq("id", cycle.id);
        if (cycleError) throw cycleError;
        const { error: profileError } = await admin
          .schema("mestre24")
          .from("professional_profiles")
          .update({
            subscription_status: "active",
            subscription_expires_at: expiresAt,
            updated_at: startsAt,
          })
          .eq("user_id", cycle.professional_user_id);
        if (profileError) throw profileError;
        // Mestre24 subscriptions are corporate revenue before the PaySuite
        // provider fee. The Central wallet receives the net amount, while
        // gross_amount and provider_fee remain available for reconciliation.
        const grossAmount = Number(cycle.amount || 0);
        const providerFee = paysuiteProviderFee(data, grossAmount);
        const netCorporateAmount = Number(Math.max(grossAmount - providerFee, 0).toFixed(2));
        const { error: financeError } = await admin.rpc("hq_ingest_platform_financial_event_v1", {
          p_platform_slug: "mestre24",
          p_source_app: "mestre24.subscriptions",
          p_transaction_type: "professional_subscription",
          p_gross_amount: grossAmount,
          p_payment_status: "confirmed",
          p_source_record_id: `mestre24:subscription:${cycle.id}`,
          p_entity_type: "subscription_cycle",
          p_entity_id: cycle.id,
          p_user_id: cycle.professional_user_id,
          p_platform_fee: netCorporateAmount,
          p_provider_fee: providerFee,
          p_partner_amount: 0,
          p_currency: "MZN",
          p_payment_method: String(cycle.provider || "mpesa"),
          p_reference: reference,
          p_metadata: {
            provider: cycle.provider,
            provider_reference: reference,
            payment_event: event,
            gross_amount: grossAmount,
            provider_fee: providerFee,
            net_corporate_amount: netCorporateAmount,
            accounting_basis: "gross_less_paysuite_fee",
          },
          p_occurred_at: startsAt,
        });
        if (financeError) throw financeError;
        return json({ ok: true, subscription: "active", cycle_id: cycle.id, expires_at: expiresAt });
      }
      if (status === "failed") {
        const { error: cycleError } = await admin
          .schema("mestre24")
          .from("subscription_cycles")
          .update({ status: "failed" })
          .eq("id", cycle.id)
          .in("status", ["pending", "paid"]);
        if (cycleError) throw cycleError;
        return json({ ok: true, subscription: "failed", cycle_id: cycle.id });
      }
      return json({ ok: true, subscription: "processing", cycle_id: cycle.id });
    }

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
