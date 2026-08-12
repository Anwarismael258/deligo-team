BEGIN;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_otp_sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_otp_channel TEXT;
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_delivery_otp_channel_check;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_delivery_otp_channel_check
  CHECK (
    delivery_otp_channel IS NULL
    OR delivery_otp_channel IN ('sms', 'push', 'in_app', 'whatsapp')
  );
DROP VIEW IF EXISTS public.order_state_snapshot;
DROP VIEW IF EXISTS public.order_state_flags;
CREATE VIEW public.order_state_flags
WITH (security_invoker = true) AS
SELECT
  o.id AS order_id,
  o.status,
  o.payment_status,
  o.funds_status,
  COALESCE(
    NULLIF(o.delivery_type, ''),
    CASE WHEN COALESCE(o.delivery_fee, 0) > 0 THEN 'delivery' ELSE 'pickup' END
  ) AS fulfillment_type,
  (
    o.status IN (
      'completed',
      'auto_completed',
      'cancelled',
      'refunded',
      'expired',
      'payment_failed'
    )
  ) AS is_final_state,
  (o.status IN ('completed', 'auto_completed')) AS is_completed_state,
  (o.status = 'disputed') AS blocks_settlement,
  (
    o.status NOT IN (
      'completed',
      'auto_completed',
      'cancelled',
      'refunded',
      'expired',
      'payment_failed'
    )
  ) AS is_operationally_active,
  (
    CASE
      WHEN COALESCE(
             NULLIF(o.delivery_type, ''),
             CASE WHEN COALESCE(o.delivery_fee, 0) > 0 THEN 'delivery' ELSE 'pickup' END
           ) = 'delivery'
        THEN o.status = 'delivered'
      ELSE o.status IN ('ready', 'awaiting_pickup_confirmation')
    END
  ) AS requires_customer_action,
  (o.status IN ('pending', 'paid', 'payment_authorized')) AS is_waiting_restaurant,
  (
    COALESCE(
      NULLIF(o.delivery_type, ''),
      CASE WHEN COALESCE(o.delivery_fee, 0) > 0 THEN 'delivery' ELSE 'pickup' END
    ) = 'delivery'
    AND o.status IN ('ready', 'courier_assigned')
  ) AS is_waiting_courier,
  (
    COALESCE(
      NULLIF(o.delivery_type, ''),
      CASE WHEN COALESCE(o.delivery_fee, 0) > 0 THEN 'delivery' ELSE 'pickup' END
    ) = 'delivery'
    AND o.status IN ('in_transit', 'arrived')
    AND o.delivery_otp_verified_at IS NULL
  ) AS otp_required,
  (
    COALESCE(
      NULLIF(o.delivery_type, ''),
      CASE WHEN COALESCE(o.delivery_fee, 0) > 0 THEN 'delivery' ELSE 'pickup' END
    ) = 'delivery'
    AND o.delivery_otp_generated_at IS NOT NULL
    AND o.delivery_otp_verified_at IS NULL
    AND COALESCE(o.delivery_otp_expires_at, NOW() + INTERVAL '1 second') > NOW()
  ) AS otp_available,
  (
    o.delivery_otp_sent_at IS NOT NULL
    AND o.delivery_otp_generated_at IS NOT NULL
    AND o.delivery_otp_sent_at >= o.delivery_otp_generated_at
    AND COALESCE(o.delivery_otp_channel, '') = 'sms'
  ) AS otp_sms_sent_for_current_code,
  CASE
    WHEN COALESCE(
           NULLIF(o.delivery_type, ''),
           CASE WHEN COALESCE(o.delivery_fee, 0) > 0 THEN 'delivery' ELSE 'pickup' END
         ) = 'delivery'
         AND o.status IN ('delivered', 'disputed')
      THEN COALESCE(
        o.delivery_extension_until,
        COALESCE(o.delivered_at, o.updated_at, o.created_at) + INTERVAL '10 minutes'
      )
    WHEN COALESCE(
           NULLIF(o.delivery_type, ''),
           CASE WHEN COALESCE(o.delivery_fee, 0) > 0 THEN 'delivery' ELSE 'pickup' END
         ) = 'pickup'
         AND o.status IN ('ready', 'awaiting_pickup_confirmation')
      THEN COALESCE(o.ready_at, o.updated_at, o.created_at) + INTERVAL '20 minutes'
    ELSE NULL
  END AS auto_close_deadline
FROM public.orders o;
CREATE VIEW public.order_state_snapshot
WITH (security_invoker = true) AS
SELECT
  o.*,
  f.is_final_state,
  f.is_completed_state,
  f.blocks_settlement,
  f.is_operationally_active,
  f.requires_customer_action,
  f.is_waiting_restaurant,
  f.is_waiting_courier,
  f.otp_required,
  f.otp_available,
  f.otp_sms_sent_for_current_code,
  f.auto_close_deadline
FROM public.orders o
JOIN public.order_state_flags f
  ON f.order_id = o.id;
COMMIT;
