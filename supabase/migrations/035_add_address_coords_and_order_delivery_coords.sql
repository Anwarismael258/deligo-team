-- Add coordinates to user_addresses and orders, and extend create_order_transactional

ALTER TABLE public.user_addresses
  ADD COLUMN IF NOT EXISTS latitude NUMERIC(10, 8),
  ADD COLUMN IF NOT EXISTS longitude NUMERIC(11, 8);
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_latitude NUMERIC(10, 8),
  ADD COLUMN IF NOT EXISTS delivery_longitude NUMERIC(11, 8);
CREATE OR REPLACE FUNCTION public.create_order_transactional(
  p_restaurant_id UUID,
  p_delivery_address TEXT,
  p_total_amount NUMERIC,
  p_delivery_fee NUMERIC,
  p_payment_method TEXT,
  p_items JSONB,
  p_scheduled_for TIMESTAMPTZ DEFAULT NULL,
  p_group_code TEXT DEFAULT NULL,
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

  INSERT INTO public.orders (
    client_id,
    restaurant_id,
    status,
    total_amount,
    delivery_address,
    delivery_fee,
    scheduled_for,
    group_code,
    group_owner_id,
    delivery_latitude,
    delivery_longitude,
    created_at,
    updated_at
  ) VALUES (
    auth.uid(),
    p_restaurant_id,
    'pending',
    p_total_amount,
    p_delivery_address,
    p_delivery_fee,
    p_scheduled_for,
    p_group_code,
    CASE WHEN p_group_code IS NOT NULL THEN auth.uid() ELSE NULL END,
    p_delivery_latitude,
    p_delivery_longitude,
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
  UUID, TEXT, NUMERIC, NUMERIC, TEXT, JSONB, TIMESTAMPTZ, TEXT, NUMERIC, NUMERIC
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_order_transactional(
  UUID, TEXT, NUMERIC, NUMERIC, TEXT, JSONB, TIMESTAMPTZ, TEXT, NUMERIC, NUMERIC
) TO authenticated;
