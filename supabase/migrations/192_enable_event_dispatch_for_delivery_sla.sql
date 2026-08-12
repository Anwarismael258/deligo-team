BEGIN;
DROP TRIGGER IF EXISTS trg_notify_order_delay_events ON public.order_events;
DROP FUNCTION IF EXISTS public.trg_notify_order_delay_events();
INSERT INTO public.order_event_subscriptions (
  event_topic,
  channel,
  target_role,
  handler,
  template_key,
  enabled,
  metadata
)
VALUES (
  'DELIVERY_SLA_EXCEEDED',
  'push',
  'customer',
  'send_notification',
  'order_delayed_customer',
  TRUE,
  jsonb_build_object(
    'phase', 'event_backbone',
    'migrated_by', '192_enable_event_dispatch_for_delivery_sla'
  )
)
ON CONFLICT (event_topic, channel, target_role, handler) DO UPDATE
SET template_key = EXCLUDED.template_key,
    enabled = TRUE,
    metadata = COALESCE(public.order_event_subscriptions.metadata, '{}'::jsonb) || EXCLUDED.metadata,
    updated_at = NOW();
COMMIT;
