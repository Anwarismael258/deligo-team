INSERT INTO public.order_event_subscriptions (
  event_topic,
  channel,
  target_role,
  handler,
  template_key,
  enabled,
  metadata
)
VALUES
  (
    'ORDER_DELIVERED',
    'push',
    'restaurant_owner',
    'send_notification',
    'order_delivered_restaurant_owner',
    TRUE,
    jsonb_build_object(
      'phase', 'event_backbone',
      'enabled_by', '196_enable_event_dispatch_for_order_delivered_restaurant_owner'
    )
  )
ON CONFLICT (event_topic, channel, target_role, handler)
DO UPDATE
SET
  template_key = EXCLUDED.template_key,
  enabled = TRUE,
  metadata = COALESCE(public.order_event_subscriptions.metadata, '{}'::jsonb)
    || EXCLUDED.metadata,
  updated_at = NOW();
