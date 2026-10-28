import { hqRpc, hqServiceKey, stagingRest, supabaseUrl } from "./hq-server";

type Row = Record<string, unknown>;

// The decision and in-app message are committed first. Provider delivery runs
// after the response; failures stay in the scoped durable outbox for retry.
export async function flushSarcaKycPush(notificationId?: string) {
  const idFilter = notificationId ? `&id=eq.${encodeURIComponent(notificationId)}` : "";
  const rows = await stagingRest(`push_notifications?select=id&type=like.SARCA_KYC_*&metadata->>app=eq.sarca&dispatch_status=in.(pending,failed,processing)&dispatch_attempts=lt.5&next_dispatch_attempt_at=lte.${encodeURIComponent(new Date().toISOString())}&order=created_at.asc&limit=20${idFilter}`) as Row[];
  for (const row of rows) {
    const worker = crypto.randomUUID();
    const notification = await hqRpc("claim_sarca_kyc_push_v1", { p_notification_id: row.id, p_worker: worker }, "hq") as Row | null;
    if (!notification) continue;
    try {
      const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() || hqServiceKey();
      const response = await fetch(`${supabaseUrl()}/functions/v1/notification-dispatch-control`, {
        method: "POST", headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({ user_id: notification.user_id, type: notification.type, title: notification.title, body: notification.body, action: notification.action, entity_id: notification.entity_id, channel: "kyc", data: notification.data, metadata: notification.metadata, dispatch_key: notification.dispatch_key }),
        signal: AbortSignal.timeout(15000),
      });
      if (!response.ok) throw new Error(`PUSH_PROVIDER_HTTP_${response.status}`);
      const result = await response.json() as { success?: boolean; data?: { targets?: Array<{ delivery?: string }> } };
      const delivery = result.data?.targets?.[0]?.delivery;
      if (!result.success || !["push", "in_app_only"].includes(delivery || "")) throw new Error("PUSH_PROVIDER_NOT_DELIVERED");
      await hqRpc("finish_sarca_kyc_push_v1", { p_notification_id: notification.id, p_worker_id: worker, p_status: delivery === "push" ? "sent" : "in_app_only", p_delivery: { delivery, app: "sarca" }, p_error: null }, "hq");
    } catch (error) {
      await hqRpc("finish_sarca_kyc_push_v1", { p_notification_id: notification.id, p_worker_id: worker, p_status: "failed", p_delivery: { app: "sarca" }, p_error: error instanceof Error ? error.message : "PUSH_PROVIDER_FAILED" }, "hq");
      console.error("SARCA_KYC_PUSH_RETRY_PENDING", { notificationId: notification.id });
    }
  }
}
