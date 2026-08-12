-- Let pickup customers conclude orders once the prep window has elapsed,
-- even if the restaurant-side status has not yet advanced to ready.

CREATE OR REPLACE FUNCTION public.client_confirm_pickup(
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
  v_started_at TIMESTAMPTZ;
  v_prep_minutes INTEGER;
  v_ready_by_time BOOLEAN := FALSE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF v_user_id <> COALESCE(v_order.client_id, v_order.customer_id) THEN
    RAISE EXCEPTION 'not_order_owner';
  END IF;

  IF COALESCE(v_order.delivery_type, '') <> 'pickup'
     AND COALESCE(v_order.delivery_fee, 0) > 0 THEN
    RAISE EXCEPTION 'order_not_pickup';
  END IF;

  IF v_order.status IN ('completed', 'delivered') THEN
    RETURN to_jsonb(v_order);
  END IF;

  v_started_at := COALESCE(
    v_order.preparation_started_at,
    (
      SELECT p.restaurant_confirmed_at
      FROM public.payment_splits p
      WHERE p.order_id = v_order.id
      ORDER BY p.created_at DESC NULLS LAST
      LIMIT 1
    ),
    v_order.updated_at,
    v_order.created_at
  );

  v_prep_minutes := GREATEST(COALESCE(v_order.estimated_delivery_time, 25), 1);

  IF v_order.status IN ('accepted', 'preparing')
     AND v_started_at IS NOT NULL
     AND v_started_at + make_interval(mins => v_prep_minutes) <= NOW() THEN
    v_ready_by_time := TRUE;
  END IF;

  IF v_order.status <> 'ready' AND NOT v_ready_by_time THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  UPDATE public.orders
  SET status = 'completed',
      confirmed_by_customer = TRUE,
      updated_at = NOW()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  RETURN to_jsonb(v_order);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.client_confirm_pickup(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.client_confirm_pickup(UUID) TO authenticated;
