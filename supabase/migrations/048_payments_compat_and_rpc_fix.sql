BEGIN;
ALTER TABLE IF EXISTS public.payments
  ADD COLUMN IF NOT EXISTS payment_ref TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS transaction_id TEXT,
  ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'wallet',
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
UPDATE public.payments
SET
  payment_ref = COALESCE(NULLIF(payment_ref, ''), 'PAY-' || UPPER(SUBSTRING(COALESCE(order_id::text, id::text, gen_random_uuid()::text) FROM 1 FOR 8))),
  payment_method = COALESCE(NULLIF(payment_method, ''), 'wallet'),
  updated_at = COALESCE(updated_at, created_at, NOW())
WHERE TRUE;
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
  v_user_id UUID := auth.uid();
  v_order_id UUID;
  v_item JSONB;
  v_payment_ref TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  IF p_restaurant_id IS NULL THEN
    RAISE EXCEPTION 'restaurant_id_required';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'items_required';
  END IF;

  INSERT INTO public.orders (
    id,
    client_id,
    customer_id,
    restaurant_id,
    status,
    total_amount,
    total,
    payment_status,
    delivery_fee,
    delivery_address,
    scheduled_for,
    group_code,
    group_owner_id,
    delivery_latitude,
    delivery_longitude,
    created_at,
    updated_at,
    confirmed_by_customer
  ) VALUES (
    gen_random_uuid(),
    v_user_id,
    v_user_id,
    p_restaurant_id,
    'pending',
    p_total_amount,
    p_total_amount,
    'pending',
    COALESCE(p_delivery_fee, 0),
    COALESCE(p_delivery_address, ''),
    p_scheduled_for,
    p_group_code,
    CASE WHEN p_group_code IS NOT NULL THEN v_user_id ELSE NULL END,
    p_delivery_latitude,
    p_delivery_longitude,
    NOW(),
    NOW(),
    FALSE
  ) RETURNING id INTO v_order_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.order_items (
      id,
      order_id,
      menu_item_id,
      quantity,
      price,
      unit_price,
      subtotal,
      created_at
    ) VALUES (
      gen_random_uuid(),
      v_order_id,
      (v_item->>'menu_item_id')::uuid,
      COALESCE((v_item->>'quantity')::int, 1),
      COALESCE((v_item->>'unit_price')::numeric, 0),
      COALESCE((v_item->>'unit_price')::numeric, 0),
      COALESCE((v_item->>'subtotal')::numeric, 0),
      NOW()
    );
  END LOOP;

  v_payment_ref := 'PAY-' || UPPER(SUBSTRING(v_order_id::text FROM 1 FOR 8));

  INSERT INTO public.payments (
    id,
    order_id,
    amount,
    payment_ref,
    payment_method,
    status,
    transaction_id,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_order_id,
    p_total_amount,
    v_payment_ref,
    COALESCE(NULLIF(p_payment_method, ''), 'wallet'),
    'pending',
    v_payment_ref,
    NOW(),
    NOW()
  );

  RETURN (
    SELECT jsonb_build_object(
      'id', o.id,
      'client_id', COALESCE(o.client_id, o.customer_id),
      'restaurant_id', o.restaurant_id,
      'courier_id', o.courier_id,
      'status', o.status,
      'payment_status', o.payment_status,
      'total_amount', COALESCE(o.total_amount, o.total, 0),
      'delivery_fee', COALESCE(o.delivery_fee, 0),
      'delivery_address', COALESCE(o.delivery_address, ''),
      'created_at', o.created_at,
      'updated_at', o.updated_at,
      'delivery_latitude', o.delivery_latitude,
      'delivery_longitude', o.delivery_longitude,
      'group_code', o.group_code,
      'scheduled_for', o.scheduled_for
    )
    FROM public.orders o
    WHERE o.id = v_order_id
  );
END;
$$;
REVOKE ALL ON FUNCTION public.create_order_transactional(UUID, TEXT, NUMERIC, NUMERIC, TEXT, JSONB, TIMESTAMPTZ, TEXT, NUMERIC, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_order_transactional(UUID, TEXT, NUMERIC, NUMERIC, TEXT, JSONB, TIMESTAMPTZ, TEXT, NUMERIC, NUMERIC) TO authenticated;
COMMIT;
