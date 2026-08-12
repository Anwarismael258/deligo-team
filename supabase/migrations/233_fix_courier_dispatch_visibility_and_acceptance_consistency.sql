BEGIN;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS orders_select_participants ON public.orders;
CREATE POLICY orders_select_participants
  ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    public.is_admin()
    OR auth.uid() = client_id
    OR auth.uid() = customer_id
    OR auth.uid() = courier_id
    OR EXISTS (
      SELECT 1
      FROM public.restaurants r
      WHERE r.id = orders.restaurant_id
        AND r.owner_id = auth.uid()
    )
    OR (
      courier_id IS NULL
      AND status IN ('accepted', 'preparing', 'ready')
      AND EXISTS (
        SELECT 1
        FROM public.couriers c
        WHERE c.id = auth.uid()
          AND COALESCE(c.is_suspended, false) = false
      )
    )
  );
CREATE OR REPLACE FUNCTION public.courier_accept_delivery(
  p_order_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_order public.orders%rowtype;
  v_is_courier BOOLEAN := FALSE;
  v_pickup_latitude NUMERIC;
  v_pickup_longitude NUMERIC;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = v_user_id
      AND p.role = 'courier'
  )
  INTO v_is_courier;

  IF NOT v_is_courier THEN
    RAISE EXCEPTION 'not_courier';
  END IF;

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF COALESCE(v_order.delivery_type, '') = 'pickup'
     OR COALESCE(v_order.delivery_fee, 0) <= 0 THEN
    RAISE EXCEPTION 'order_not_delivery';
  END IF;

  IF v_order.courier_id IS NOT NULL THEN
    RAISE EXCEPTION 'courier_already_assigned';
  END IF;

  IF v_order.status NOT IN ('accepted', 'preparing', 'ready') THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  UPDATE public.orders
  SET courier_id = v_user_id,
      status = 'courier_assigned',
      updated_at = NOW()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  SELECT r.latitude, r.longitude
  INTO v_pickup_latitude, v_pickup_longitude
  FROM public.restaurants r
  WHERE r.id = v_order.restaurant_id
  LIMIT 1;

  INSERT INTO public.deliveries (
    order_id,
    courier_id,
    pickup_latitude,
    pickup_longitude,
    delivery_latitude,
    delivery_longitude,
    status,
    updated_at
  )
  VALUES (
    v_order.id,
    v_user_id,
    v_pickup_latitude,
    v_pickup_longitude,
    v_order.delivery_latitude,
    v_order.delivery_longitude,
    'courier_assigned',
    NOW()
  )
  ON CONFLICT (order_id) DO UPDATE
  SET courier_id = EXCLUDED.courier_id,
      pickup_latitude = COALESCE(EXCLUDED.pickup_latitude, public.deliveries.pickup_latitude),
      pickup_longitude = COALESCE(EXCLUDED.pickup_longitude, public.deliveries.pickup_longitude),
      delivery_latitude = COALESCE(EXCLUDED.delivery_latitude, public.deliveries.delivery_latitude),
      delivery_longitude = COALESCE(EXCLUDED.delivery_longitude, public.deliveries.delivery_longitude),
      status = 'courier_assigned',
      updated_at = NOW();

  RETURN to_jsonb(v_order);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.courier_accept_delivery(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.courier_accept_delivery(UUID) TO authenticated;
COMMIT;
