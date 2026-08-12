BEGIN;
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
  v_restaurant_id UUID;
  v_courier_id UUID;
BEGIN
  IF p_entity_type = 'restaurant' THEN
    SELECT r.id
    INTO v_restaurant_id
    FROM public.restaurants r
    WHERE r.id = p_entity_id
       OR r.owner_id = p_entity_id
       OR r.id = (
         SELECT o.restaurant_id
         FROM public.orders o
         WHERE o.id = p_order_id
         LIMIT 1
       )
    ORDER BY CASE
      WHEN r.id = p_entity_id THEN 0
      WHEN r.owner_id = p_entity_id THEN 1
      ELSE 2
    END
    LIMIT 1;
  ELSIF p_entity_type = 'courier' THEN
    SELECT c.id
    INTO v_courier_id
    FROM public.couriers c
    WHERE c.id = p_entity_id
       OR c.user_id = p_entity_id
       OR c.id = (
         SELECT o.courier_id
         FROM public.orders o
         WHERE o.id = p_order_id
         LIMIT 1
       )
    ORDER BY CASE
      WHEN c.id = p_entity_id THEN 0
      WHEN c.user_id = p_entity_id THEN 1
      ELSE 2
    END
    LIMIT 1;
  END IF;

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
        restaurant_id = COALESCE(public.payouts.restaurant_id, v_restaurant_id),
        courier_id = COALESCE(public.payouts.courier_id, v_courier_id),
        metadata = COALESCE(public.payouts.metadata, '{}'::jsonb) || COALESCE(p_metadata, '{}'::jsonb),
        processed_at = COALESCE(public.payouts.processed_at, NOW()),
        updated_at = NOW()
    WHERE id = v_payout_id;
  END IF;

  RETURN v_payout_id;
END;
$$;
COMMIT;
