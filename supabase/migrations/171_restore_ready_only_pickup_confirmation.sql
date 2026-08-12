BEGIN;
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

  IF v_order.status <> 'ready' THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  BEGIN
    EXECUTE 'ALTER TABLE public.orders DISABLE TRIGGER USER';
    UPDATE public.orders
    SET status = 'completed',
        confirmed_by_customer = TRUE,
        updated_at = NOW()
    WHERE id = p_order_id
    RETURNING * INTO v_order;
    EXECUTE 'ALTER TABLE public.orders ENABLE TRIGGER USER';
  EXCEPTION WHEN OTHERS THEN
    EXECUTE 'ALTER TABLE public.orders ENABLE TRIGGER USER';
    RAISE;
  END;

  RETURN to_jsonb(v_order);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.client_confirm_pickup(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.client_confirm_pickup(UUID) TO authenticated;
COMMIT;
