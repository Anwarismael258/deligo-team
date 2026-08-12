BEGIN;
CREATE OR REPLACE FUNCTION public.restaurant_update_order_status(
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
  v_order RECORD;
  v_allowed BOOLEAN := FALSE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  IF p_status IS NULL OR btrim(p_status) = '' THEN
    RAISE EXCEPTION 'status_required';
  END IF;

  SELECT o.*
  INTO v_order
  FROM public.orders o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.restaurants r
    WHERE r.id = v_order.restaurant_id
      AND r.owner_id = v_user_id
  )
  INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'restaurant_not_authorized';
  END IF;

  IF p_status NOT IN ('accepted', 'preparing', 'ready', 'cancelled') THEN
    RAISE EXCEPTION 'invalid_restaurant_status';
  END IF;

  UPDATE public.orders
  SET status = p_status,
      updated_at = NOW()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order.id,
    'status', v_order.status,
    'updated_at', v_order.updated_at
  );
END;
$$;
REVOKE ALL ON FUNCTION public.restaurant_update_order_status(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.restaurant_update_order_status(UUID, TEXT) TO authenticated;
COMMIT;
