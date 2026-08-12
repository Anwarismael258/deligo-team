BEGIN;
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

  IF v_order.status NOT IN ('accepted', 'ready') THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  UPDATE public.orders
  SET courier_id = v_user_id,
      status = 'courier_assigned',
      updated_at = NOW()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  RETURN to_jsonb(v_order);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.courier_accept_delivery(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.courier_accept_delivery(UUID) TO authenticated;
CREATE OR REPLACE FUNCTION public.courier_update_order_status(
  p_order_id UUID,
  p_status TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_order public.orders%rowtype;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  IF p_status IS NULL OR btrim(p_status) = '' THEN
    RAISE EXCEPTION 'status_required';
  END IF;

  IF p_status NOT IN ('arrived', 'in_transit', 'delivered') THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF v_order.courier_id IS NULL OR v_order.courier_id <> v_user_id THEN
    RAISE EXCEPTION 'not_assigned_courier';
  END IF;

  IF COALESCE(v_order.delivery_type, '') = 'pickup'
     OR COALESCE(v_order.delivery_fee, 0) <= 0 THEN
    RAISE EXCEPTION 'order_not_delivery';
  END IF;

  IF p_status = 'arrived'
     AND v_order.status NOT IN ('courier_assigned', 'accepted', 'ready') THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  IF p_status = 'in_transit'
     AND v_order.status NOT IN ('courier_assigned', 'ready', 'arrived') THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  IF p_status = 'delivered'
     AND v_order.status NOT IN ('in_transit', 'arrived') THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  UPDATE public.orders
  SET status = p_status,
      updated_at = NOW()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  RETURN to_jsonb(v_order);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.courier_update_order_status(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.courier_update_order_status(UUID, TEXT) TO authenticated;
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

  IF v_user_id NOT IN (v_order.client_id, v_order.customer_id) THEN
    RAISE EXCEPTION 'not_order_owner';
  END IF;

  IF COALESCE(v_order.delivery_type, '') <> 'pickup'
     AND COALESCE(v_order.delivery_fee, 0) > 0 THEN
    RAISE EXCEPTION 'order_not_pickup';
  END IF;

  IF v_order.status <> 'ready' THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  UPDATE public.orders
  SET status = 'completed',
      updated_at = NOW()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  RETURN to_jsonb(v_order);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.client_confirm_pickup(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.client_confirm_pickup(UUID) TO authenticated;
COMMIT;
