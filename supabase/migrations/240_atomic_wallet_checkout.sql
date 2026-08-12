BEGIN;
CREATE OR REPLACE FUNCTION public.create_order_transactional_with_wallet_payment(
  p_restaurant_id UUID,
  p_delivery_address TEXT,
  p_total_amount NUMERIC,
  p_delivery_fee NUMERIC,
  p_payment_method TEXT,
  p_items JSONB,
  p_scheduled_for TIMESTAMPTZ DEFAULT NULL,
  p_group_code TEXT DEFAULT NULL,
  p_delivery_type TEXT DEFAULT 'delivery',
  p_delivery_latitude NUMERIC DEFAULT NULL,
  p_delivery_longitude NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order JSONB;
  v_order_id UUID;
  v_payment_method TEXT := LOWER(COALESCE(NULLIF(btrim(p_payment_method), ''), 'wallet'));
BEGIN
  v_order := public.create_order_transactional(
    p_restaurant_id := p_restaurant_id,
    p_delivery_address := p_delivery_address,
    p_total_amount := p_total_amount,
    p_delivery_fee := p_delivery_fee,
    p_payment_method := v_payment_method,
    p_items := p_items,
    p_scheduled_for := p_scheduled_for,
    p_group_code := p_group_code,
    p_delivery_type := p_delivery_type,
    p_delivery_latitude := p_delivery_latitude,
    p_delivery_longitude := p_delivery_longitude
  );

  v_order_id := NULLIF(v_order->>'id', '')::UUID;

  IF v_order_id IS NULL THEN
    RAISE EXCEPTION 'order_creation_failed';
  END IF;

  IF v_payment_method <> 'wallet' THEN
    RETURN v_order;
  END IF;

  PERFORM public.process_wallet_order_payment(v_order_id, auth.uid());

  RETURN (
    SELECT to_jsonb(o.*)
    FROM public.orders o
    WHERE o.id = v_order_id
  );
END;
$$;
REVOKE ALL ON FUNCTION public.create_order_transactional_with_wallet_payment(
  UUID, TEXT, NUMERIC, NUMERIC, TEXT, JSONB, TIMESTAMPTZ, TEXT, TEXT, NUMERIC, NUMERIC
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_order_transactional_with_wallet_payment(
  UUID, TEXT, NUMERIC, NUMERIC, TEXT, JSONB, TIMESTAMPTZ, TEXT, TEXT, NUMERIC, NUMERIC
) TO authenticated;
COMMIT;
