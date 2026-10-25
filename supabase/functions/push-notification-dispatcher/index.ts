import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm";
import { deliverPushNotification } from "../_shared/notification_dispatch.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const dispatchSecret = Deno.env.get("FCM_DISPATCH_SECRET") ?? "";
const supabase = createClient(supabaseUrl, serviceRoleKey);

type NotificationRow = Record<string, unknown> & {
  id: string;
  user_id: string;
  title: string;
  body: string;
  type?: string | null;
  action?: string | null;
  entity_id?: string | null;
  priority?: string | null;
  channel?: string | null;
  data?: Record<string, unknown> | null;
  metadata?: Record<string, unknown> | null;
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function authorized(request: Request) {
  if (!dispatchSecret) return true;
  const provided = request.headers.get("x-fcm-dispatch-secret") ||
    request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") || "";
  return provided.length > 0 && provided === dispatchSecret;
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Supabase service configuration is missing" }, 500);
  if (!authorized(request)) return json({ error: "Unauthorized" }, 401);

  const payload = await request.json().catch(() => ({})) as { limit?: number };
  const limit = Math.min(100, Math.max(1, Number(payload.limit) || 50));
  const workerId = `fcm:${crypto.randomUUID()}`;
  const { data: claimed, error: claimError } = await supabase.rpc("claim_pending_push_notifications", {
    p_worker_id: workerId,
    p_limit: limit,
  });

  if (claimError) return json({ error: "Could not claim notification queue", detail: claimError.message }, 502);

  const results: Array<Record<string, unknown>> = [];
  for (const raw of (claimed ?? []) as NotificationRow[]) {
    try {
      const data = {
        ...record(raw.metadata),
        ...record(raw.data),
        id: raw.id,
        type: raw.type ?? "SYSTEM_ALERT",
        action: raw.action ?? "",
        entity_id: raw.entity_id ?? "",
        priority: raw.priority ?? "NORMAL",
        channel: raw.channel ?? "system",
      };
      const delivery = await deliverPushNotification({
        supabase,
        userId: raw.user_id,
        title: raw.title,
        body: raw.body,
        data,
        allowInAppOnlyFallback: true,
      });
      const { error: markError } = await supabase.rpc("mark_push_notification_dispatched", {
        p_notification_id: raw.id,
        p_worker_id: workerId,
        p_status: delivery.delivery,
        p_delivery: {
          tokens_count: delivery.tokensCount,
          message_ids: delivery.messageIds ?? [],
          failed_tokens: delivery.failedTokens ?? 0,
        },
        p_error: delivery.errors?.join("; ") ?? null,
      });
      if (markError) throw new Error(markError.message);
      results.push({ id: raw.id, status: delivery.delivery, tokens: delivery.tokensCount });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await supabase.rpc("mark_push_notification_dispatched", {
        p_notification_id: raw.id,
        p_worker_id: workerId,
        p_status: "failed",
        p_delivery: {},
        p_error: message.slice(0, 1000),
      });
      results.push({ id: raw.id, status: "failed", error: message });
    }
  }

  return json({ ok: true, worker_id: workerId, claimed: results.length, results });
});
