BEGIN;
INSERT INTO public.order_event_subscriptions (
  event_topic,
  channel,
  target_role,
  handler,
  template_key,
  enabled,
  metadata
)
SELECT
  'DRIVER_AT_RESTAURANT_CUSTOMER',
  'push',
  'customer',
  'send_notification',
  'driver_at_restaurant_customer',
  FALSE,
  jsonb_build_object('phase', 'critical_notification_control')
WHERE NOT EXISTS (
  SELECT 1
  FROM public.order_event_subscriptions
  WHERE event_topic = 'DRIVER_AT_RESTAURANT_CUSTOMER'
    AND channel = 'push'
    AND target_role = 'customer'
    AND template_key = 'driver_at_restaurant_customer'
);
INSERT INTO public.order_event_subscriptions (
  event_topic,
  channel,
  target_role,
  handler,
  template_key,
  enabled,
  metadata
)
SELECT
  'DRIVER_AT_RESTAURANT_RESTAURANT',
  'push',
  'restaurant_owner',
  'send_notification',
  'driver_at_restaurant_restaurant',
  FALSE,
  jsonb_build_object('phase', 'critical_notification_control')
WHERE NOT EXISTS (
  SELECT 1
  FROM public.order_event_subscriptions
  WHERE event_topic = 'DRIVER_AT_RESTAURANT_RESTAURANT'
    AND channel = 'push'
    AND target_role = 'restaurant_owner'
    AND template_key = 'driver_at_restaurant_restaurant'
);
INSERT INTO public.order_event_subscriptions (
  event_topic,
  channel,
  target_role,
  handler,
  template_key,
  enabled,
  metadata
)
SELECT
  'ORDER_DELIVERED_COURIER',
  'push',
  'courier',
  'send_notification',
  'order_delivered_courier',
  FALSE,
  jsonb_build_object('phase', 'critical_notification_control')
WHERE NOT EXISTS (
  SELECT 1
  FROM public.order_event_subscriptions
  WHERE event_topic = 'ORDER_DELIVERED_COURIER'
    AND channel = 'push'
    AND target_role = 'courier'
    AND template_key = 'order_delivered_courier'
);
INSERT INTO public.order_event_subscriptions (
  event_topic,
  channel,
  target_role,
  handler,
  template_key,
  enabled,
  metadata
)
SELECT
  'ORDER_DELIVERED_RESTAURANT',
  'push',
  'restaurant_owner',
  'send_notification',
  'order_delivered_restaurant',
  FALSE,
  jsonb_build_object('phase', 'critical_notification_control')
WHERE NOT EXISTS (
  SELECT 1
  FROM public.order_event_subscriptions
  WHERE event_topic = 'ORDER_DELIVERED_RESTAURANT'
    AND channel = 'push'
    AND target_role = 'restaurant_owner'
    AND template_key = 'order_delivered_restaurant'
);
COMMIT;
