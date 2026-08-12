BEGIN;
ALTER TABLE IF EXISTS public.payouts
  ADD COLUMN IF NOT EXISTS restaurant_id UUID,
  ADD COLUMN IF NOT EXISTS courier_id UUID;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'payouts'
      AND column_name = 'restaurant_id'
      AND is_nullable = 'NO'
  ) THEN
    EXECUTE 'ALTER TABLE public.payouts ALTER COLUMN restaurant_id DROP NOT NULL';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'payouts'
      AND column_name = 'courier_id'
      AND is_nullable = 'NO'
  ) THEN
    EXECUTE 'ALTER TABLE public.payouts ALTER COLUMN courier_id DROP NOT NULL';
  END IF;
END $$;
CREATE OR REPLACE FUNCTION public.upsert_payout(
  p_order_id UUID,
  p_payout_type TEXT,
  p_entity_type TEXT,
  p_entity_id UUID,
  p_amount NUMERIC,
  p_currency TEXT,
  p_idempotency_key TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payout_id UUID;
  v_restaurant_id UUID := CASE WHEN p_entity_type = 'restaurant' THEN p_entity_id ELSE NULL END;
  v_courier_id UUID := CASE WHEN p_entity_type = 'courier' THEN p_entity_id ELSE NULL END;
BEGIN
  SELECT id
  INTO v_payout_id
  FROM public.payouts
  WHERE idempotency_key = p_idempotency_key
  LIMIT 1
  FOR UPDATE;

  IF v_payout_id IS NULL THEN
    INSERT INTO public.payouts (
      order_id,
      payout_type,
      entity_type,
      entity_id,
      restaurant_id,
      courier_id,
      amount,
      currency,
      status,
      idempotency_key,
      metadata,
      processed_at
    ) VALUES (
      p_order_id,
      p_payout_type,
      p_entity_type,
      p_entity_id,
      v_restaurant_id,
      v_courier_id,
      COALESCE(p_amount, 0),
      COALESCE(NULLIF(p_currency, ''), 'MZN'),
      'paid',
      p_idempotency_key,
      COALESCE(p_metadata, '{}'::jsonb),
      NOW()
    )
    RETURNING id INTO v_payout_id;
  ELSE
    UPDATE public.payouts
    SET amount = COALESCE(p_amount, 0),
        currency = COALESCE(NULLIF(p_currency, ''), 'MZN'),
        status = 'paid',
        entity_type = COALESCE(entity_type, p_entity_type),
        entity_id = COALESCE(entity_id, p_entity_id),
        restaurant_id = COALESCE(restaurant_id, v_restaurant_id),
        courier_id = COALESCE(courier_id, v_courier_id),
        metadata = COALESCE(public.payouts.metadata, '{}'::jsonb) || COALESCE(p_metadata, '{}'::jsonb),
        processed_at = COALESCE(public.payouts.processed_at, NOW()),
        updated_at = NOW()
    WHERE id = v_payout_id;
  END IF;

  RETURN v_payout_id;
END;
$$;
COMMIT;
