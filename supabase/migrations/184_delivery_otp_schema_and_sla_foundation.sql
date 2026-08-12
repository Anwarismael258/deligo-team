BEGIN;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS preparing_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ready_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS picked_up_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_otp_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_otp_generated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_otp_verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_otp_regeneration_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS delivery_extension_until TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_extension_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dispute_reason TEXT,
  ADD COLUMN IF NOT EXISTS dispute_created_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;
CREATE TABLE IF NOT EXISTS public.delivery_otp_secrets (
  order_id UUID PRIMARY KEY REFERENCES public.orders(id) ON DELETE CASCADE,
  otp_code TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  verified_at TIMESTAMPTZ NULL,
  regeneration_count INTEGER NOT NULL DEFAULT 0,
  last_regenerated_at TIMESTAMPTZ NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT delivery_otp_code_format_check CHECK (otp_code ~ '^[0-9]{4}$'),
  CONSTRAINT delivery_otp_regeneration_count_check CHECK (regeneration_count >= 0)
);
ALTER TABLE public.delivery_otp_secrets ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policy
    WHERE polname = 'delivery_otp_secrets_select_owner'
      AND polrelid = 'public.delivery_otp_secrets'::regclass
  ) THEN
    CREATE POLICY delivery_otp_secrets_select_owner
      ON public.delivery_otp_secrets
      FOR SELECT
      TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.orders o
          WHERE o.id = order_id
            AND auth.uid() = COALESCE(o.client_id, o.customer_id)
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policy
    WHERE polname = 'delivery_otp_secrets_service_all'
      AND polrelid = 'public.delivery_otp_secrets'::regclass
  ) THEN
    CREATE POLICY delivery_otp_secrets_service_all
      ON public.delivery_otp_secrets
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
DO $$
DECLARE
  c_name TEXT;
BEGIN
  SELECT conname
  INTO c_name
  FROM pg_constraint
  WHERE conrelid = 'public.orders'::regclass
    AND contype = 'c'
    AND conname = 'orders_status_check';

  IF c_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.orders DROP CONSTRAINT %I', c_name);
  END IF;
END;
$$;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
  CHECK (
    status IN (
      'pending',
      'paid',
      'payment_authorized',
      'accepted',
      'preparing',
      'ready',
      'awaiting_pickup_confirmation',
      'picked_up',
      'in_delivery',
      'courier_assigned',
      'on_the_way',
      'in_transit',
      'arrived',
      'delivered',
      'disputed',
      'completed',
      'auto_completed',
      'expired',
      'payment_failed',
      'refunded',
      'cancelled'
    )
  );
CREATE OR REPLACE FUNCTION public.validate_order_transition(
  p_from_status TEXT,
  p_to_status TEXT,
  p_delivery_type TEXT DEFAULT 'delivery'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_from TEXT := LOWER(COALESCE(p_from_status, ''));
  v_to TEXT := LOWER(COALESCE(p_to_status, ''));
  v_delivery_type TEXT := LOWER(COALESCE(p_delivery_type, 'delivery'));
BEGIN
  IF v_from = '' OR v_to = '' THEN
    RETURN FALSE;
  END IF;

  IF v_from = v_to THEN
    RETURN TRUE;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM (
      VALUES
        ('pending', 'payment_authorized', NULL),
        ('pending', 'paid', NULL),
        ('pending', 'payment_failed', NULL),
        ('pending', 'cancelled', NULL),
        ('paid', 'accepted', NULL),
        ('paid', 'expired', NULL),
        ('paid', 'cancelled', NULL),
        ('payment_authorized', 'accepted', NULL),
        ('payment_authorized', 'expired', NULL),
        ('payment_authorized', 'cancelled', NULL),
        ('accepted', 'preparing', NULL),
        ('preparing', 'ready', NULL),
        ('ready', 'awaiting_pickup_confirmation', 'pickup'),
        ('awaiting_pickup_confirmation', 'completed', 'pickup'),
        ('ready', 'completed', 'pickup'),
        ('ready', 'auto_completed', 'pickup'),
        ('ready', 'picked_up', 'delivery'),
        ('picked_up', 'in_delivery', 'delivery'),
        ('in_delivery', 'arrived', 'delivery'),
        ('ready', 'courier_assigned', 'delivery'),
        ('courier_assigned', 'in_transit', 'delivery'),
        ('ready', 'in_transit', 'delivery'),
        ('in_transit', 'arrived', 'delivery'),
        ('in_transit', 'delivered', 'delivery'),
        ('arrived', 'delivered', 'delivery'),
        ('delivered', 'completed', 'delivery'),
        ('delivered', 'auto_completed', 'delivery'),
        ('delivered', 'disputed', 'delivery'),
        ('cancelled', 'refunded', NULL),
        ('expired', 'refunded', NULL)
    ) AS allowed(from_status, to_status, delivery_type)
    WHERE allowed.from_status = v_from
      AND allowed.to_status = v_to
      AND (allowed.delivery_type IS NULL OR allowed.delivery_type = v_delivery_type)
  );
END;
$$;
COMMIT;
