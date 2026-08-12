-- Add per-order preparation time and compute from menu items
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS estimated_delivery_time INTEGER;
UPDATE public.orders o
SET estimated_delivery_time = COALESCE(
  (
    SELECT MAX(mi.prep_time_minutes)
    FROM public.order_items oi
    JOIN public.menu_items mi ON mi.id = oi.menu_item_id
    WHERE oi.order_id = o.id
  ),
  (
    SELECT r.estimated_delivery_time
    FROM public.restaurants r
    WHERE r.id = o.restaurant_id
  ),
  25
)
WHERE o.estimated_delivery_time IS NULL
  OR o.estimated_delivery_time <= 0;
CREATE OR REPLACE FUNCTION public.create_order_transactional(
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
  v_order_id UUID;
  v_payment_id UUID;
  v_item JSONB;
  v_delivery_type TEXT := COALESCE(NULLIF(p_delivery_type, ''), 'delivery');
  v_prep_minutes INTEGER;
BEGIN
  IF p_restaurant_id IS NULL THEN
    RAISE EXCEPTION 'restaurant_id is required';
  END IF;
  IF p_total_amount IS NULL OR p_total_amount <= 0 THEN
    RAISE EXCEPTION 'total_amount must be > 0';
  END IF;
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'items cannot be empty';
  END IF;

  SELECT COALESCE(
    (
      SELECT MAX(mi.prep_time_minutes)
      FROM public.menu_items mi
      WHERE mi.id IN (
        SELECT (value->>'menu_item_id')::UUID
        FROM jsonb_array_elements(p_items) AS value
      )
    ),
    (
      SELECT r.estimated_delivery_time
      FROM public.restaurants r
      WHERE r.id = p_restaurant_id
    ),
    25
  ) INTO v_prep_minutes;

  INSERT INTO public.orders (
    client_id,
    restaurant_id,
    status,
    delivery_address,
    total_amount,
    delivery_fee,
    payment_method,
    scheduled_for,
    group_code,
    delivery_type,
    delivery_latitude,
    delivery_longitude,
    estimated_delivery_time,
    created_at,
    updated_at
  ) VALUES (
    auth.uid(),
    p_restaurant_id,
    'pending',
    p_delivery_address,
    p_total_amount,
    p_delivery_fee,
    p_payment_method,
    p_scheduled_for,
    p_group_code,
    v_delivery_type,
    p_delivery_latitude,
    p_delivery_longitude,
    v_prep_minutes,
    NOW(),
    NOW()
  )
  RETURNING id INTO v_order_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.order_items (
      order_id,
      menu_item_id,
      quantity,
      unit_price,
      subtotal,
      created_at
    ) VALUES (
      v_order_id,
      (v_item->>'menu_item_id')::UUID,
      (v_item->>'quantity')::INT,
      (v_item->>'unit_price')::NUMERIC,
      (v_item->>'subtotal')::NUMERIC,
      NOW()
    );
  END LOOP;

  INSERT INTO public.payments (
    order_id,
    amount,
    payment_method,
    status,
    created_at,
    updated_at
  ) VALUES (
    v_order_id,
    p_total_amount,
    p_payment_method,
    'pending',
    NOW(),
    NOW()
  )
  RETURNING id INTO v_payment_id;

  RETURN (
    SELECT to_jsonb(o.*)
    FROM public.orders o
    WHERE o.id = v_order_id
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.create_order_transactional(
  UUID, TEXT, NUMERIC, NUMERIC, TEXT, JSONB, TIMESTAMPTZ, TEXT, TEXT, NUMERIC, NUMERIC
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_order_transactional(
  UUID, TEXT, NUMERIC, NUMERIC, TEXT, JSONB, TIMESTAMPTZ, TEXT, TEXT, NUMERIC, NUMERIC
) TO authenticated;
