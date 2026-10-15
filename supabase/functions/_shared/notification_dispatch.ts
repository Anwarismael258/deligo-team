import admin from "npm:firebase-admin";

const HIGH_IMPORTANCE_CHANNEL_ID = "high_importance_v3";
const COURIER_DISPATCH_CHANNEL_ID = "courier_dispatch_v3";
const RESTAURANT_ORDERS_CHANNEL_ID = "restaurant_orders_v4";
const CLIENT_ALERT_CHANNEL_ID = "client_alert_v3";
const CRITICAL_SOUND_NAME = "short_bang";
const RESTAURANT_ORDER_SOUND_NAME = "platinum_1";

let adminApp: admin.app.App | null = null;

type SupabaseClientLike = {
  from: (...args: unknown[]) => any;
  rpc: (...args: unknown[]) => Promise<{ data?: unknown; error?: { message?: string } | null }>;
};

export type DispatchNotificationInput = {
  userId: string;
  type: string;
  title: string;
  body: string;
  action?: string | null;
  entityId?: string | null;
  priority?: string | null;
  channel?: string | null;
  data?: Record<string, unknown> | null;
  metadata?: Record<string, unknown> | null;
  dispatchKey?: string | null;
  sourceEventId?: string | null;
};

export type DispatchNotificationResult = {
  notificationId: string;
  delivery: "push" | "in_app_only" | "push_failed";
  pushEnabled: boolean;
  tokensCount: number;
  messageIds?: string[];
  failedTokens?: number;
};

export type PushTransportResult = {
  delivery: "push" | "in_app_only" | "push_failed";
  pushEnabled: boolean;
  tokensCount: number;
  messageIds?: string[];
  failedTokens?: number;
  errors?: string[];
  permanentFailure?: boolean;
};

function parseFirebaseServiceAccount(rawValue: string) {
  const candidates = new Set<string>();
  candidates.add(rawValue);

  const trimmed = rawValue.trim();
  candidates.add(trimmed);

  if (
    (trimmed.startsWith("'") && trimmed.endsWith("'")) ||
    (trimmed.startsWith('"') && trimmed.endsWith('"'))
  ) {
    candidates.add(trimmed.slice(1, -1));
  }

  for (const candidate of candidates) {
    if (!candidate) continue;
    const normalized = candidate.replace(/\\n/g, "\n");
    try {
      return JSON.parse(normalized);
    } catch {
      // try next strategy
    }

    const singleQuoteNormalized = normalized
      .replace(/([{,]\s*)'([^']+?)'\s*:/g, '$1"$2":')
      .replace(/:\s*'([^']*?)'(\s*[,}])/g, ':"$1"$2');
    try {
      return JSON.parse(singleQuoteNormalized);
    } catch {
      // try next strategy
    }

    try {
      const decoded = atob(normalized);
      return JSON.parse(decoded);
    } catch {
      // try next strategy
    }
  }

  throw new Error(
    "FIREBASE_SERVICE_ACCOUNT is not valid JSON. Check quotes/escaping in Supabase secret.",
  );
}

function initFirebaseAdmin() {
  if (adminApp) return adminApp;
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "";
  if (!raw.trim()) return null;
  const serviceAccount = parseFirebaseServiceAccount(raw);
  adminApp = admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
  return adminApp;
}

function toRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function isCourierDispatchNotification(data: Record<string, string>) {
  return data.type === "DELIVERY_OPPORTUNITY" ||
    data.type === "NEW_DRIVER_ORDER" ||
    data.type === "ORDER_READY_FOR_PICKUP" ||
    data.channel === "courier_dispatch";
}

function isClientAlertNotification(data: Record<string, string>) {
  return data.type === "ORDER_READY" ||
    data.type === "DRIVER_ASSIGNED" ||
    data.channel === "client_alert";
}

function isRestaurantOrderNotification(data: Record<string, string>) {
  return data.type === "NEW_ORDER" ||
    data.type === "NEW_PAID_ORDER" ||
    data.channel === "restaurant_order_alert" ||
    data.channel === "restaurant";
}

function resolveAndroidChannelId(data: Record<string, string>) {
  if (isCourierDispatchNotification(data)) return COURIER_DISPATCH_CHANNEL_ID;
  if (isRestaurantOrderNotification(data)) return RESTAURANT_ORDERS_CHANNEL_ID;
  if (isClientAlertNotification(data)) return CLIENT_ALERT_CHANNEL_ID;
  return HIGH_IMPORTANCE_CHANNEL_ID;
}

function resolveAndroidSound(data: Record<string, string>) {
  if (isRestaurantOrderNotification(data)) return RESTAURANT_ORDER_SOUND_NAME;
  return isCourierDispatchNotification(data) ||
      isClientAlertNotification(data)
    ? CRITICAL_SOUND_NAME
    : "default";
}

function buildAndroidNotificationConfig(data: Record<string, string>) {
  const sound = resolveAndroidSound(data);
  return {
    channelId: resolveAndroidChannelId(data),
    ...(sound === "default" ? {} : { sound }),
    clickAction: "FLUTTER_NOTIFICATION_CLICK",
    tag: data.id || data.entity_id || data.order_id || undefined,
  };
}

function buildApsPayload(
  data: Record<string, string>,
  title?: string,
  body?: string,
) {
  const aps: admin.messaging.Aps = {
    sound: "default",
    badge: 1,
  };

  if ((title?.trim() ?? "").length > 0 || (body?.trim() ?? "").length > 0) {
    aps.alert = {
      title: title?.trim() || undefined,
      body: body?.trim() || undefined,
    };
  }

  if (
    isCourierDispatchNotification(data) ||
    isRestaurantOrderNotification(data) ||
    isClientAlertNotification(data)
  ) {
    const mutableAps = aps as unknown as Record<string, unknown>;
    mutableAps["interruption-level"] = "time-sensitive";
    mutableAps["content-available"] = 1;
  }

  return aps;
}

function isPermanentPushError(error: unknown) {
  const message = error instanceof Error ? error.message.toLowerCase() : String(error).toLowerCase();
  return message.includes("registration-token-not-registered") ||
    message.includes("invalid-registration-token") ||
    message.includes("requested entity was not found");
}

async function deactivatePushToken(supabase: SupabaseClientLike, token: string) {
  if (!token.trim()) return;
  await supabase
    .from("user_push_tokens")
    .update({
      is_active: false,
      last_seen_at: new Date().toISOString(),
    })
    .eq("token", token);
}

export async function loadPushContext(supabase: SupabaseClientLike, userId: string) {
  const [{ data: tokenRows }, { data: profile }] = await Promise.all([
    supabase
      .from("user_push_tokens")
      .select("token")
      .eq("user_id", userId)
      .eq("is_active", true)
      .order("last_seen_at", { ascending: false })
      .limit(20),
    supabase
      .from("profiles")
      .select("fcm_token, settings")
      .eq("id", userId)
      .maybeSingle(),
  ]);

  const activeTokens = new Set<string>(
    (tokenRows ?? [])
      .map((row: Record<string, unknown>) => row.token?.toString().trim() ?? "")
      .filter((value: string) => value.length > 0),
  );

  const legacyToken = profile?.fcm_token?.toString().trim() ?? "";
  if (legacyToken) {
    activeTokens.add(legacyToken);
  }

  const settings = profile?.settings && typeof profile.settings === "object"
    ? profile.settings as Record<string, unknown>
    : {};
  const notifications = settings.notifications && typeof settings.notifications === "object"
    ? settings.notifications as Record<string, unknown>
    : {};

  return {
    pushEnabled: notifications.push !== false,
    tokens: Array.from(activeTokens),
  };
}

async function createNotificationRecord(
  supabase: SupabaseClientLike,
  input: DispatchNotificationInput,
) {
  const metadata = {
    ...toRecord(input.metadata),
    ...toRecord(input.data),
  };
  const { data, error } = await supabase.rpc("create_app_notification", {
    p_user_id: input.userId,
    p_type: input.type,
    p_title: input.title,
    p_body: input.body,
    p_action: input.action ?? null,
    p_entity_id: input.entityId ?? null,
    p_priority: input.priority ?? "NORMAL",
    p_channel: input.channel ?? "system",
    p_metadata: metadata,
    p_source_event_id: input.sourceEventId ?? null,
    p_dispatch_key: input.dispatchKey ?? null,
  });

  if (error || !data) {
    throw new Error(error?.message || "create_app_notification_failed");
  }

  return String(data);
}

async function logDispatchEvent(
  supabase: SupabaseClientLike,
  event: string,
  metadata: Record<string, unknown>,
) {
  try {
    await supabase.from("webhook_events").insert({
      event,
      metadata: JSON.stringify(metadata),
    });
  } catch {
    // Logging must never block the caller.
  }
}

export function buildPushPayloadData(data: Record<string, unknown> | null | undefined) {
  return {
    click_action: "FLUTTER_NOTIFICATION_CLICK",
    ...Object.fromEntries(
      Object.entries(toRecord(data)).map(([key, value]) => [key, String(value ?? "")]),
    ),
  };
}

type DeliverPushInput = {
  supabase: SupabaseClientLike;
  title: string;
  body: string;
  data?: Record<string, unknown> | null;
  userId?: string | null;
  explicitTokens?: string[] | null;
  allowInAppOnlyFallback?: boolean;
};

export async function deliverPushNotification(
  input: DeliverPushInput,
): Promise<PushTransportResult> {
  const userId = input.userId?.trim() ?? "";
  const explicitTokens = (input.explicitTokens ?? [])
    .map((value) => value.trim())
    .filter((value) => value.length > 0);

  let pushEnabled = true;
  let tokens = explicitTokens;
  if (tokens.length === 0) {
    if (!userId) {
      throw new Error("user_id is required when explicit tokens are not provided");
    }

    const pushContext = await loadPushContext(input.supabase, userId);
    pushEnabled = pushContext.pushEnabled;
    tokens = pushContext.tokens;

    if (!pushEnabled || tokens.length === 0) {
      return {
        delivery: "in_app_only",
        pushEnabled,
        tokensCount: tokens.length,
      };
    }
  }

  const app = initFirebaseAdmin();
  if (!app) {
    if (input.allowInAppOnlyFallback) {
      return {
        delivery: "in_app_only",
        pushEnabled,
        tokensCount: tokens.length,
      };
    }
    throw new Error("Firebase Admin SDK was not initialized");
  }

  const payloadData = buildPushPayloadData({
    ...toRecord(input.data),
    title: input.title,
    body: input.body,
  });
  const messaging = admin.messaging(app);
  const messageIds: string[] = [];
  const failedErrors: string[] = [];

  for (const token of tokens) {
    try {
      const messageId = await messaging.send({
        token,
        notification: {
          title: input.title,
          body: input.body,
        },
        data: payloadData,
        android: {
          priority: "high",
          notification: buildAndroidNotificationConfig(payloadData),
        },
        apns: {
          headers: {
            "apns-priority": "10",
          },
          payload: {
            aps: buildApsPayload(payloadData, input.title, input.body),
          },
        },
      });
      messageIds.push(messageId);
    } catch (error) {
      if (isPermanentPushError(error)) {
        await deactivatePushToken(input.supabase, token);
      }
      failedErrors.push(error instanceof Error ? error.message : String(error));
    }
  }

  if (messageIds.length > 0) {
    return {
      delivery: "push",
      pushEnabled,
      tokensCount: tokens.length,
      messageIds,
      failedTokens: failedErrors.length,
      errors: failedErrors,
      permanentFailure: false,
    };
  }

  return {
    delivery: "push_failed",
    pushEnabled,
    tokensCount: tokens.length,
    failedTokens: failedErrors.length,
    errors: failedErrors,
    permanentFailure: failedErrors.length > 0 &&
      failedErrors.every((message) => isPermanentPushError(message)),
  };
}

export async function deliverPushNotificationToTopic(
  topic: string,
  title: string,
  body: string,
  data?: Record<string, unknown> | null,
) {
  const app = initFirebaseAdmin();
  if (!app) {
    throw new Error("Firebase Admin SDK was not initialized");
  }

  const payloadData = buildPushPayloadData(data);
  return await admin.messaging(app).send({
    topic,
    notification: {
      title,
      body,
    },
    data: buildPushPayloadData({
      ...toRecord(data),
      title,
      body,
    }),
    android: {
      priority: "high",
      notification: buildAndroidNotificationConfig(
        buildPushPayloadData({
          ...toRecord(data),
          title,
          body,
        }),
      ),
    },
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: buildApsPayload(payloadData, title, body),
      },
    },
  });
}

export async function dispatchNotificationToUser(
  supabase: SupabaseClientLike,
  input: DispatchNotificationInput,
): Promise<DispatchNotificationResult> {
  const userId = input.userId.trim();
  if (!userId) {
    throw new Error("user_id is required");
  }

  const notificationId = await createNotificationRecord(supabase, {
    ...input,
    userId,
  });

  const pushContext = await loadPushContext(supabase, userId);
  if (!pushContext.pushEnabled || pushContext.tokens.length === 0) {
    await logDispatchEvent(supabase, "notification_dispatch_in_app_only", {
      user_id: userId,
      notification_id: notificationId,
      type: input.type,
      channel: input.channel ?? "system",
      push_enabled: pushContext.pushEnabled,
      tokens_count: pushContext.tokens.length,
    });
    return {
      notificationId,
      delivery: "in_app_only",
      pushEnabled: pushContext.pushEnabled,
      tokensCount: pushContext.tokens.length,
    };
  }

  const delivery = await deliverPushNotification({
    supabase,
    userId,
    title: input.title,
    body: input.body,
    data: {
      ...toRecord(input.data),
      id: notificationId,
      type: input.type,
      action: input.action ?? "",
      entity_id: input.entityId ?? "",
      priority: input.priority ?? "NORMAL",
      channel: input.channel ?? "system",
      title: input.title,
      body: input.body,
    },
    allowInAppOnlyFallback: true,
  });

  if (delivery.delivery === "push") {
    await logDispatchEvent(supabase, "notification_dispatch_sent", {
      user_id: userId,
      notification_id: notificationId,
      type: input.type,
      channel: input.channel ?? "system",
      tokens_count: delivery.tokensCount,
      failed_tokens: delivery.failedTokens ?? 0,
      message_ids: delivery.messageIds ?? [],
    });
    return {
      notificationId,
      delivery: "push",
      pushEnabled: delivery.pushEnabled,
      tokensCount: delivery.tokensCount,
      messageIds: delivery.messageIds,
      failedTokens: delivery.failedTokens,
    };
  }

  if (delivery.delivery === "in_app_only") {
    await logDispatchEvent(supabase, "notification_dispatch_push_unavailable", {
      user_id: userId,
      notification_id: notificationId,
      type: input.type,
      channel: input.channel ?? "system",
      tokens_count: delivery.tokensCount,
    });
  } else {
    await logDispatchEvent(supabase, "notification_dispatch_push_failed", {
      user_id: userId,
      notification_id: notificationId,
      type: input.type,
      channel: input.channel ?? "system",
      tokens_count: delivery.tokensCount,
      errors: delivery.errors ?? [],
    });
  }

  return {
    notificationId,
    delivery: delivery.delivery,
    pushEnabled: delivery.pushEnabled,
    tokensCount: delivery.tokensCount,
    failedTokens: delivery.failedTokens,
  };
}

export async function loadUsersByRole(
  supabase: SupabaseClientLike,
  role: string,
) {
  const { data, error } = await supabase
    .from("profiles")
    .select("id")
    .eq("role", role);

  if (error) {
    throw new Error(`Failed to load users by role: ${error.message}`);
  }

  return (data ?? [])
    .map((row: Record<string, unknown>) => row.id?.toString().trim() ?? "")
    .filter((value: string) => value.length > 0);
}
