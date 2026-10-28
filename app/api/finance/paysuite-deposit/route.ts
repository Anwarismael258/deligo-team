import { randomUUID } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqServiceKey, supabaseUrl } from "@/lib/hq-server";
import { paysuiteRequest } from "@/lib/paysuite";

export const dynamic = "force-dynamic";

type DepositBody = {
  amount?: number;
  paymentMethod?: string;
  phone?: string;
  idempotencyKey?: string;
};

const paymentHeaders = (key: string) => ({
  apikey: key,
  Authorization: `Bearer ${key}`,
  "Content-Type": "application/json",
  "Accept-Profile": "payments",
  "Content-Profile": "payments",
});

function normalizePhone(value: string) {
  const digits = value.replace(/\D/g, "");
  const normalized = digits.startsWith("258") ? `+${digits}` : `+258${digits.replace(/^0/, "")}`;
  return /^\+258\d{9}$/.test(normalized) ? normalized : null;
}

export async function POST(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor || !["SUPER_ADMIN", "FINANCE"].includes(actor.role)) {
    return NextResponse.json({ error: "Apenas Admin ou Finanças podem iniciar um depósito PaySuite." }, { status: 403 });
  }

  const body = await request.json().catch(() => null) as DepositBody | null;
  const amount = Number(body?.amount);
  const method = String(body?.paymentMethod || "").trim().toLowerCase();
  const phone = normalizePhone(String(body?.phone || ""));
  if (!Number.isFinite(amount) || amount <= 0 || amount > 10_000_000 || !["mpesa", "emola", "card"].includes(method) || !phone) {
    return NextResponse.json({ error: "Indique um valor válido, método PaySuite e número M-Pesa/e-Mola válido." }, { status: 400 });
  }

  const url = supabaseUrl();
  const key = hqServiceKey();
  if (!key) return NextResponse.json({ error: "Backend financeiro não configurado." }, { status: 503 });

  const reference = `HQ-CORPORATE-DEPOSIT:${actor.employee_id}:${randomUUID()}`;
  const idempotencyKey = String(body?.idempotencyKey || reference).trim();
  try {
    const provider = await paysuiteRequest<Record<string, unknown>>("/payments", {
      method: "POST",
      body: JSON.stringify({
        amount: Number(amount.toFixed(2)),
        currency: "MZN",
        payment_method: method,
        customer_phone: phone,
        reference,
        metadata: {
          destination: "hq_corporate_wallet",
          actor_employee_id: actor.employee_id,
          actor_auth_user_id: actor.authUserId,
          idempotency_key: idempotencyKey,
        },
      }),
    });
    const paymentData = provider.data && typeof provider.data === "object" && !Array.isArray(provider.data) ? provider.data as Record<string, unknown> : provider;
    const checkoutUrl = String(paymentData.checkout_url || paymentData.checkoutUrl || paymentData.url || "");
    const providerId = String(paymentData.id || paymentData.payment_id || "");
    if (!providerId) return NextResponse.json({ error: "PaySuite não devolveu uma referência de pagamento." }, { status: 502 });

    const amountMinor = Math.round(amount * 100);
    const inserted = await fetch(`${url}/rest/v1/payment_transactions`, {
      method: "POST",
      headers: { ...paymentHeaders(key), Prefer: "return=representation" },
      body: JSON.stringify({
        app_id: null,
        initiator_user_id: actor.authUserId,
        wallet_account_id: null,
        transaction_type: "topup",
        status: "pending",
        funds_status: "none",
        amount_minor: amountMinor,
        fee_minor: 0,
        provider: "paysuite",
        provider_reference: providerId,
        external_reference: reference,
        metadata: {
          destination: "hq_corporate_wallet",
          actor_employee_id: actor.employee_id,
          payment_method: method,
          customer_phone: phone,
          checkout_url: checkoutUrl || null,
          idempotency_key: idempotencyKey,
        },
      }),
    });
    if (!inserted.ok) return NextResponse.json({ error: "PaySuite criou o pagamento, mas a Central não conseguiu guardar a operação." }, { status: 503 });
    const [payment] = await inserted.json() as Array<Record<string, unknown>>;
    return NextResponse.json({
      paymentId: payment?.id,
      providerId,
      checkoutUrl: checkoutUrl || null,
      status: "pending",
      message: "Depósito iniciado. O saldo só será actualizado após confirmação do webhook assinado da PaySuite.",
    }, { status: 201 });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "PaySuite indisponível." }, { status: 502 });
  }
}
