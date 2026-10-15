import { randomUUID } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { paysuiteRequest } from "../../../../../lib/paysuite";

type CreateBody = {
  platform?: string;
  order_id?: string;
  wallet_id?: string;
  amount?: number;
  currency?: string;
  payment_method?: string;
  customer_phone?: string;
  idempotency_key?: string;
};

const jsonHeaders = (key: string) => ({ apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json", "Accept-Profile": "payments", "Content-Profile": "payments" });

export async function POST(request: NextRequest) {
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const url = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!token || !url || !serviceKey) return NextResponse.json({ error: "Sessão ou backend não configurado." }, { status: 401 });

  const identity = await fetch(`${url}/auth/v1/user`, { headers: { apikey: serviceKey, Authorization: `Bearer ${token}` } });
  if (!identity.ok) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401 });
  const user = await identity.json() as { id?: string; phone?: string };
  const body = await request.json().catch(() => null) as CreateBody | null;
  const amount = Number(body?.amount);
  const platform = body?.platform?.trim() || "deligo";
  const currency = body?.currency?.trim().toUpperCase() || "MZN";
  const method = body?.payment_method?.trim().toLowerCase();
  const phone = body?.customer_phone?.trim() || user.phone;
  if (!user.id || !Number.isFinite(amount) || amount <= 0 || currency !== "MZN" || !phone || !method || !["mpesa", "emola", "card"].includes(method)) {
    return NextResponse.json({ error: "Dados de pagamento inválidos." }, { status: 400 });
  }

  const reference = `DLG-${platform}-${body?.order_id || body?.wallet_id || user.id}-${randomUUID()}`;
  const idempotency = body?.idempotency_key?.trim() || reference;
  const existing = await fetch(`${url}/rest/v1/payment_transactions?select=id,status,provider_reference,external_reference,metadata&external_reference=eq.${encodeURIComponent(idempotency)}&limit=1`, { headers: jsonHeaders(serviceKey) });
  if (existing.ok) {
    const rows = await existing.json() as Array<Record<string, unknown>>;
    if (rows[0]) return NextResponse.json({ payment_id: rows[0].id, status: rows[0].status, checkout_url: (rows[0].metadata as Record<string, unknown> | undefined)?.checkout_url || null, idempotent: true });
  }

  let provider: Record<string, unknown>;
  try {
    provider = await paysuiteRequest<Record<string, unknown>>("/payments", { method: "POST", body: JSON.stringify({ amount, currency, payment_method: method, customer_phone: phone, reference, metadata: { platform, order_id: body?.order_id || null, wallet_id: body?.wallet_id || null } }) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "PaySuite indisponível." }, { status: 502 });
  }
  const checkoutUrl = String(provider.checkout_url || provider.checkoutUrl || provider.url || "");
  const providerId = String(provider.id || provider.payment_id || "");
  if (!checkoutUrl || !providerId) return NextResponse.json({ error: "Resposta PaySuite sem checkout válido." }, { status: 502 });

  const inserted = await fetch(`${url}/rest/v1/payment_transactions`, { method: "POST", headers: { ...jsonHeaders(serviceKey), Prefer: "return=representation" }, body: JSON.stringify({ initiator_user_id: user.id, transaction_type: body?.order_id ? "payment" : "topup", status: "pending", funds_status: "none", amount_minor: Math.round(amount * 100), provider: "paysuite", provider_reference: providerId, external_reference: idempotency, platform_slug: platform, method, metadata: { checkout_url: checkoutUrl, order_id: body?.order_id || null, wallet_id: body?.wallet_id || null, currency, customer_phone: phone } }) });
  if (!inserted.ok) return NextResponse.json({ error: "Pagamento criado no provedor, mas não foi guardado na Central." }, { status: 503 });
  const saved = (await inserted.json() as Array<Record<string, unknown>>)[0];
  return NextResponse.json({ payment_id: saved?.id, status: "pending", checkout_url: checkoutUrl, provider_id: providerId });
}
