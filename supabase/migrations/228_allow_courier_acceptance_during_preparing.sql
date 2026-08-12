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

  IF v_order.status NOT IN ('accepted', 'preparing', 'ready') THEN
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
COMMIT;
