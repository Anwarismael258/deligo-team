import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm";
import { dispatchNotificationToUser } from "../_shared/notification_dispatch.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, supabaseKey);

async function notifyCriticalOrderParticipant(params: {
  orderId: string;
  targetRole: "customer" | "courier" | "restaurant_owner";
  targetUserId: string;
  type: string;
  title: string;
  body: string;
  action?: string | null;
  priority?: string;
  channel?: string;
  data?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}) {
  const response = await fetch(
    `${supabaseUrl}/functions/v1/order-critical-notification-control`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: supabaseKey,
        Authorization: `Bearer ${supabaseKey}`,
      },
      body: JSON.stringify({
        order_id: params.orderId,
        target_role: params.targetRole,
        target_user_id: params.targetUserId,
        type: params.type,
        title: params.title,
        body: params.body,
        action: params.action ?? "OPEN_ORDER",
        priority: params.priority ?? "HIGH",
        channel: params.channel ?? "system",
        data: params.data ?? {},
        metadata: {
          dispatch_source: "create-payment-critical",
          ...(params.metadata ?? {}),
          ...(params.data ?? {}),
        },
      }),
    },
  );

  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload?.success !== true) {
    throw new Error(
      payload?.error?.toString?.() ||
        `order-critical-notification-control_failed_${response.status}`,
    );
  }
}

function readAccessToken(req: Request): string | null {
  const authHeader = req.headers.get("authorization") ||
    req.headers.get("Authorization") ||
    "";
  if (!authHeader.startsWith("Bearer ")) return null;
  const token = authHeader.slice(7).trim();
  return token.length > 0 ? token : null;
}

async function getAuthenticatedUserId(accessToken: string): Promise<string | null> {
  try {
    const userResponse = await supabase.auth.getUser(accessToken);
    if (userResponse.error || !userResponse.data?.user) {
      return null;
    }
    const userId = userResponse.data.user.id;
    if (typeof userId !== "string") return null;
    const normalizedUserId = userId.trim();
    return normalizedUserId.length > 0 ? normalizedUserId : null;
  } catch {
    return null;
  }
}

async function notifyUser(params: {
  userId: string;
  type: string;
  title: string;
  body: string;
  action?: string | null;
  entityId?: string | null;
  priority?: string;
  channel?: string;
  metadata?: Record<string, unknown>;
  dispatchKey?: string | null;
}) {
  try {
    const payloadMetadata = {
      dispatch_source: "create-payment",
      dispatch_retry_mode: "backend_control",
      ...(params.metadata ?? {}),
    };

    await dispatchNotificationToUser(supabase, {
      userId: params.userId,
      type: params.type,
      title: params.title,
      body: params.body,
      action: params.action ?? null,
      entityId: params.entityId ?? null,
      priority: params.priority ?? "NORMAL",
      channel: params.channel ?? "system",
      data: payloadMetadata,
      metadata: payloadMetadata,
      dispatchKey: params.dispatchKey ?? null,
    });
  } catch (notificationError) {
    console.warn("Falha ao despachar notificacao:", notificationError);
  }
}

async function appendOrderEvent(params: {
  orderId: string;
  eventType: string;
  actorId?: string | null;
  actorRole?: string | null;
  payload?: Record<string, unknown>;
  idempotencyKey?: string | null;
  correlationId?: string | null;
}) {
  try {
    const { error } = await supabase.rpc("append_order_event", {
      p_order_id: params.orderId,
      p_event_type: params.eventType,
      p_actor_id: params.actorId ?? null,
      p_actor_role: params.actorRole ?? null,
      p_payload: params.payload ?? {},
      p_idempotency_key: params.idempotencyKey ?? null,
      p_correlation_id: params.correlationId ?? params.orderId,
    });

    if (error) {
      throw error;
    }
  } catch (error) {
    console.warn("Falha ao registar order_event:", error);
  }
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ success: false, error: "Method not allowed" }),
      { status: 405, headers: { "Content-Type": "application/json" } },
    );
  }

  try {
    const accessToken = readAccessToken(req);
    if (!accessToken) {
      return new Response(
        JSON.stringify({ success: false, error: "Unauthorized" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const userId = await getAuthenticatedUserId(accessToken);
    if (!userId) {
      return new Response(
        JSON.stringify({ success: false, error: "Invalid token" }),
        { status: 401, headers: { "Content-Type": "application/json" } },
      );
    }

    const { amount, order_id } = await req.json();

    if (!amount || !order_id) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing required fields" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const { data: result, error: rpcError } = await supabase.rpc(
      "process_wallet_order_payment",
      {
        p_order_id: order_id,
        p_user_id: userId,
      },
    );

    if (rpcError || !result) {
      const message = rpcError?.message || "Nao foi possivel debitar a carteira";
      const normalizedMessage = message.toLowerCase();
      const insufficientFunds = normalizedMessage.includes("insufficient_balance") ||
        normalizedMessage.includes("insufficient_available_balance");
      const status = insufficientFunds ? 400 : 500;

      await appendOrderEvent({
        orderId: order_id,
        eventType: "payment_failed",
        actorId: userId,
        actorRole: "customer",
        payload: {
          order_id,
          amount,
          reason: message,
          status,
        },
        idempotencyKey: `payment-failed:${order_id}:${message.toLowerCase()}`,
      });

      await notifyUser({
        userId,
        type: "PAYMENT_FAILED",
        title: "Pagamento falhou",
        body: insufficientFunds
          ? "O pedido nao foi pago porque a carteira nao tem saldo suficiente."
          : "Nao foi possivel concluir o pagamento do pedido agora.",
        action: insufficientFunds ? "OPEN_WALLET" : "OPEN_ORDER",
        entityId: order_id,
        priority: "HIGH",
        channel: "payment",
        metadata: {
          order_id,
          reason: message,
          amount,
        },
        dispatchKey: `payment_failed:${userId}:${order_id}:${insufficientFunds ? "insufficient_funds" : "provider_error"}`,
      });

      return new Response(
        JSON.stringify({
          success: false,
          error: insufficientFunds
            ? "Saldo insuficiente na carteira para pagar este pedido."
            : message,
        }),
        { status, headers: { "Content-Type": "application/json" } },
      );
    }

    await appendOrderEvent({
      orderId: order_id,
      eventType: "payment_confirmed",
      actorId: userId,
      actorRole: "customer",
      payload: {
        order_id,
        amount,
        payment_ref: result.payment_ref,
        status: result.status || "completed",
        escrow_amount: result.escrow_amount,
      },
      idempotencyKey: `payment-confirmed:${order_id}`,
    });

    await notifyUser({
      userId,
      type: "PAYMENT_CONFIRMED",
      title: "Pagamento confirmado",
      body: "O valor saiu da sua carteira e o pedido foi enviado ao restaurante.",
      action: "OPEN_ORDER",
      entityId: order_id,
      priority: "HIGH",
      channel: "payment",
      metadata: {
        order_id,
        payment_ref: result.payment_ref,
        status: result.status || "completed",
        escrow_amount: result.escrow_amount,
      },
      dispatchKey: `payment_confirmed:${userId}:${order_id}`,
    });

    try {
      const { data: orderRow } = await supabase
        .from("orders")
        .select("restaurant_id,total_amount,delivery_fee,delivery_type,delivery_address")
        .eq("id", order_id)
        .maybeSingle();

      const restaurantId = orderRow?.restaurant_id?.toString?.();
      if (restaurantId) {
        const { data: restaurant } = await supabase
          .from("restaurants")
          .select("owner_id, name")
          .eq("id", restaurantId)
          .maybeSingle();

        const ownerId = restaurant?.owner_id?.toString?.();
        if (ownerId) {
          const orderRef = String(order_id).slice(0, 8).toUpperCase();
          const totalAmount = Number(orderRow?.total_amount ?? 0);
          const totalLabel = Number.isFinite(totalAmount) && totalAmount > 0
            ? `${totalAmount.toFixed(0)} MZN`
            : "valor confirmado";
          const restaurantOrderBody =
            `Pedido pago #${orderRef} - ${totalLabel}. Abra para ver os detalhes e aceitar.`;
          try {
            await notifyCriticalOrderParticipant({
              orderId: order_id,
              targetRole: "restaurant_owner",
              targetUserId: ownerId,
              type: "NEW_PAID_ORDER",
              title: "Novo pedido pago",
              body: restaurantOrderBody,
              action: "OPEN_ORDER",
              priority: "HIGH",
              channel: "restaurant",
              data: {
                order_id,
                order_ref: orderRef,
                total_amount: orderRow?.total_amount ?? null,
                delivery_fee: orderRow?.delivery_fee ?? null,
                delivery_type: orderRow?.delivery_type ?? null,
                delivery_address: orderRow?.delivery_address ?? null,
              },
              metadata: {
                order_id,
                restaurant_id: restaurantId,
                restaurant_name: restaurant?.name ?? null,
                payment_ref: result.payment_ref,
              },
            });
          } catch (criticalRestaurantNotificationError) {
            console.warn(
              "Falha no dispatch critico do restaurante, usando fallback direto:",
              criticalRestaurantNotificationError,
            );
            await notifyUser({
              userId: ownerId,
              type: "NEW_PAID_ORDER",
              title: "Novo pedido pago",
              body: restaurantOrderBody,
              action: "OPEN_ORDER",
              entityId: order_id,
              priority: "HIGH",
              channel: "restaurant",
              metadata: {
                order_id,
                restaurant_id: restaurantId,
                restaurant_name: restaurant?.name ?? null,
                payment_ref: result.payment_ref,
              },
              dispatchKey: `new_paid_order:${ownerId}:${order_id}`,
            });
          }
        }
      }
    } catch (restaurantNotificationError) {
      console.warn("Falha ao notificar restaurante:", restaurantNotificationError);
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          payment_ref: result.payment_ref,
          status: result.status || "completed",
          provider_reference: null,
          payment_instructions:
            "Pagamento realizado com a carteira interna e valor reservado em escrow.",
          qr_code: null,
          wallet_balance: result.wallet_balance,
          escrow_amount: result.escrow_amount,
        },
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("Erro create-payment:", error);

    try {
      const accessToken = readAccessToken(req);
      const userId = accessToken
        ? await getAuthenticatedUserId(accessToken)
        : null;
      const requestBody = await req.clone().json().catch(() => ({}));
      const orderId = requestBody?.order_id?.toString?.();

      if (userId && orderId) {
        const errorMessage = error instanceof Error ? error.message : "Erro interno";
        await appendOrderEvent({
          orderId,
          eventType: "payment_failed",
          actorId: userId,
          actorRole: "customer",
          payload: {
            order_id: orderId,
            error: errorMessage,
            reason: "internal_error",
          },
          idempotencyKey: `payment-failed:${orderId}:internal_error`,
        });

        await notifyUser({
          userId,
          type: "PAYMENT_FAILED",
          title: "Pagamento falhou",
          body: "O pedido nao foi pago agora. Tente novamente em alguns instantes.",
          action: "OPEN_ORDER",
          entityId: orderId,
          priority: "HIGH",
          channel: "payment",
          metadata: {
            order_id: orderId,
            error: errorMessage,
          },
          dispatchKey: `payment_failed:${userId}:${orderId}:internal_error`,
        });
      }
    } catch (_) {
      // Ignora falha secundaria de notificacao.
    }

    return new Response(
      JSON.stringify({
        success: false,
        error:
          error instanceof Error
            ? error.message
            : "Erro interno ao iniciar pagamento",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
