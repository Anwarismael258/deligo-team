import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm";
import { dispatchNotificationToUser } from "../_shared/notification_dispatch.ts";
import { getDebitoPayConfig } from "../_shared/payment_providers.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, supabaseKey);
const GATEWAY_DEPOSIT_FEE_PERCENT = 0.03;
const webhookSecret = getDebitoPayConfig().webhookSecret;

function normalizeStatus(value?: string | null): string {
  const status = String(value || "").trim().toLowerCase();
  if (["completed", "success", "paid", "approved"].includes(status)) return "completed";
  if (["pending", "processing"].includes(status)) return "pending";
  return "failed";
}

function escapeFilterValue(value: string): string {
  return value.replace(/\\/g, "\\\\").replace(/,/g, "\\,");
}

function collectReferenceCandidates(payload: Record<string, unknown>): string[] {
  const rawCandidates = [
    payload.reference,
    payload.reference_description,
    payload.reference_text,
    payload.internal_reference,
    payload.external_reference,
    payload.debito_reference,
    payload.transaction_id,
    payload.provider_reference,
    payload.id,
    payload.data && typeof payload.data === "object"
      ? (payload.data as Record<string, unknown>).reference
      : null,
    payload.data && typeof payload.data === "object"
      ? (payload.data as Record<string, unknown>).reference_description
      : null,
    payload.data && typeof payload.data === "object"
      ? (payload.data as Record<string, unknown>).debito_reference
      : null,
    payload.data && typeof payload.data === "object"
      ? (payload.data as Record<string, unknown>).transaction_id
      : null,
  ];

  return Array.from(
    new Set(
      rawCandidates
        .map((value) => String(value || "").trim())
        .filter((value) => value.length > 0),
    ),
  );
}

function normalizeMsisdn(value?: string | null): string {
  const digits = String(value || "").replace(/[^\d]/g, "");
  if (digits.startsWith("258") && digits.length >= 12) {
    return digits.slice(3);
  }
  return digits;
}

function collectPhoneCandidates(payload: Record<string, unknown>): string[] {
  const nested = payload.data && typeof payload.data === "object"
    ? payload.data as Record<string, unknown>
    : null;

  return Array.from(
    new Set(
      [
        payload.msisdn,
        payload.phone_number,
        payload.customer_msisdn,
        payload.customer_phone,
        nested?.msisdn,
        nested?.phone_number,
        nested?.customer_msisdn,
        nested?.customer_phone,
      ]
        .map((value) => normalizeMsisdn(String(value || "")))
        .filter((value) => value.length >= 9),
    ),
  );
}

async function findDepositByFallback(params: {
  amount: number;
  phoneCandidates: string[];
}) {
  if (params.amount <= 0 || params.phoneCandidates.length === 0) {
    return null;
  }

  const sinceIso = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data, error } = await supabase
    .from("wallet_deposits")
    .select(
      "id, wallet_id, user_id, status, reference, amount, processed_at, phone_number, created_at",
    )
    .eq("status", "pending")
    .eq("amount", params.amount)
    .gte("created_at", sinceIso)
    .order("created_at", { ascending: false })
    .limit(20);

  if (error || !data) return null;

  return data.find((deposit) => {
    const normalizedPhone = normalizeMsisdn(deposit.phone_number?.toString());
    return params.phoneCandidates.includes(normalizedPhone);
  }) ?? null;
}

async function notifyDepositConfirmed(params: {
  userId: string | null;
  depositId: string;
  walletId: string;
  amount: number;
  netAmount: number;
  gatewayFee: number;
  providerStatus?: string | null;
  transactionId?: string | null;
}) {
  const userId = params.userId?.trim() ?? "";
  if (!userId) return;

  const title = "Deposito confirmado";
  const body = `Recebemos ${params.netAmount.toFixed(2)} MZN na sua carteira.`;
  const metadata = {
    deposit_id: params.depositId,
    wallet_id: params.walletId,
    gross_amount: params.amount,
    net_amount: params.netAmount,
    gateway_fee: params.gatewayFee,
    provider_status: params.providerStatus ?? null,
    transaction_id: params.transactionId ?? null,
  };

  try {
    await dispatchNotificationToUser(supabase, {
      userId,
      type: "WALLET_DEPOSIT_CONFIRMED",
      title,
      body,
      action: "OPEN_WALLET",
      entityId: params.depositId,
      priority: "HIGH",
      channel: "wallet",
      data: metadata,
      metadata: {
        source: "wallet_deposit_webhook",
        ...metadata,
      },
      dispatchKey: `wallet_deposit_confirmed:${userId}:${params.depositId}`,
    });
  } catch (error) {
    console.warn("wallet-deposit-webhook notification dispatch failed:", error);
  }
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    if (webhookSecret) {
      const providedSecret =
        new URL(req.url).searchParams.get("token") ||
        req.headers.get("x-webhook-secret") ||
        req.headers.get("x-signature") ||
        req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ||
        "";

      if (!providedSecret || providedSecret !== webhookSecret) {
        return new Response(JSON.stringify({
          status: "unauthorized",
          message: "Webhook secret invalido",
        }), {
          status: 401,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    const payload = await req.json();
    const referenceCandidates = collectReferenceCandidates(payload);
    const phoneCandidates = collectPhoneCandidates(payload);
    const statusRaw = String(payload.status || payload.state || "").toLowerCase();
    const providerStatus = String(
      payload.status || payload.state || payload.transaction_status || "",
    ).trim() || null;
    const amount = Number(payload.amount || payload.total || 0);

    if (referenceCandidates.length === 0) {
      return new Response(JSON.stringify({ status: "ignored", message: "Referencia ausente" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const filter = referenceCandidates
      .flatMap((candidate) => [
        `reference.eq.${escapeFilterValue(candidate)}`,
        `transaction_id.eq.${escapeFilterValue(candidate)}`,
      ])
      .join(",");

    const { data: matchedByReference, error: depositError } = await supabase
      .from("wallet_deposits")
      .select("id, wallet_id, user_id, status, reference, amount, processed_at")
      .or(filter)
      .maybeSingle();

    const deposit = matchedByReference ??
      await findDepositByFallback({
        amount,
        phoneCandidates,
      });

    if (depositError || !deposit) {
      return new Response(JSON.stringify({
        status: "ignored",
        message: "Deposito nao encontrado",
        candidates: referenceCandidates,
        phone_candidates: phoneCandidates,
      }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (deposit.status !== "pending" || deposit.processed_at) {
      return new Response(JSON.stringify({ status: "ignored", message: "Deposito ja processado" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const newStatus = normalizeStatus(statusRaw);
    const grossAmount = amount > 0 ? amount : Number(deposit.amount || 0);
    const gatewayFee = Number((grossAmount * GATEWAY_DEPOSIT_FEE_PERCENT).toFixed(2));
    const netAmount = Number((grossAmount - gatewayFee).toFixed(2));
    const transactionId = String(
      payload.debito_reference ||
        payload.transaction_id ||
        payload.id ||
        referenceCandidates[0] ||
        "",
    ).trim() || null;

    const processedAt = newStatus === "completed" ? new Date().toISOString() : null;
    const { data: updatedRows } = await supabase
      .from("wallet_deposits")
      .update({
        status: newStatus,
        provider_status: providerStatus,
        provider_payload: payload,
        gateway_fee: gatewayFee,
        net_amount: netAmount,
        transaction_id: transactionId,
        processed_at: processedAt,
        updated_at: new Date().toISOString(),
      })
      .eq("id", deposit.id)
      .is("processed_at", null)
      .select("id");

    if (newStatus === "completed" && (!updatedRows || updatedRows.length === 0)) {
      return new Response(JSON.stringify({ status: "ignored", message: "Deposito ja reconciliado" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (newStatus === "completed") {
      const { data: existingNetLedger } = await supabase
        .from("wallet_ledger")
        .select("id")
        .eq("entry_type", "deposit_net")
        .contains("metadata", { deposit_id: deposit.id })
        .maybeSingle();

      if (existingNetLedger) {
        await notifyDepositConfirmed({
          userId: deposit.user_id || null,
          depositId: deposit.id,
          walletId: deposit.wallet_id,
          amount: grossAmount,
          netAmount,
          gatewayFee,
          providerStatus,
          transactionId,
        });

        return new Response(JSON.stringify({ status: "ignored", message: "Deposito ja reconciliado" }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }

      const { data: wallet } = await supabase
        .from("wallets")
        .select("id,user_id")
        .eq("id", deposit.wallet_id)
        .single();

      await supabase.rpc("apply_wallet_ledger_entry", {
        p_wallet_id: deposit.wallet_id,
        p_user_id: wallet?.user_id || null,
        p_direction: "credit",
        p_entry_type: "deposit_net",
        p_amount: netAmount,
        p_reference_key: `deposit-net-${deposit.id}`,
        p_metadata: {
          deposit_id: deposit.id,
          gross_amount: grossAmount,
          gateway_fee: gatewayFee,
          provider: payload.provider || null,
        },
        p_status: "confirmed",
      });

      await supabase.rpc("apply_wallet_ledger_entry", {
        p_wallet_id: null,
        p_user_id: wallet?.user_id || null,
        p_direction: "debit",
        p_entry_type: "deposit_gateway_fee",
        p_amount: gatewayFee,
        p_reference_key: `deposit-fee-${deposit.id}`,
        p_metadata: {
          deposit_id: deposit.id,
          gross_amount: grossAmount,
          provider: payload.provider || null,
        },
        p_status: "confirmed",
      });

      await notifyDepositConfirmed({
        userId: wallet?.user_id || deposit.user_id || null,
        depositId: deposit.id,
        walletId: deposit.wallet_id,
        amount: grossAmount,
        netAmount,
        gatewayFee,
        providerStatus,
        transactionId,
      });
    }

    return new Response(JSON.stringify({
      status: "ok",
      message: `Deposito ${newStatus}`,
    }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Erro no webhook:", error);
    return new Response(JSON.stringify({
      status: "error",
      message: error instanceof Error ? error.message : "Erro interno",
    }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
