BEGIN;
CREATE OR REPLACE FUNCTION public.client_confirm_pickup_v2(
  p_order_id UUID,
  p_customer_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := COALESCE(auth.uid(), p_customer_id);
  v_order public.orders%rowtype;
  v_platform_user_id UUID;
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

  IF v_order.status IN ('completed', 'auto_completed', 'delivered') THEN
    RETURN to_jsonb(v_order);
  END IF;

  IF v_order.status <> 'ready' THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  v_platform_user_id := public.resolve_platform_user_id();

  PERFORM public.process_delivery_settlement(
    p_order_id := p_order_id,
    p_customer_id := v_user_id,
    p_platform_user_id := v_platform_user_id
  );

  BEGIN
    EXECUTE 'ALTER TABLE public.orders DISABLE TRIGGER USER';
    UPDATE public.orders
    SET status = 'completed',
        confirmed_by_customer = TRUE,
        order_completed_at = COALESCE(order_completed_at, NOW()),
        settlement_processed_at = COALESCE(settlement_processed_at, NOW()),
        updated_at = NOW()
    WHERE id = p_order_id
    RETURNING * INTO v_order;
    EXECUTE 'ALTER TABLE public.orders ENABLE TRIGGER USER';
  EXCEPTION WHEN OTHERS THEN
    EXECUTE 'ALTER TABLE public.orders ENABLE TRIGGER USER';
    RAISE;
  END;

  INSERT INTO public.order_events (
    order_id,
    event_type,
    actor_id,
    actor_role,
    old_status,
    new_status,
    metadata
  ) VALUES (
    p_order_id,
    'pickup_confirmed_by_customer',
    v_user_id,
    'customer',
    'ready',
    'completed',
    jsonb_build_object(
      'source', 'client_confirm_pickup_v2',
      'confirmed_by_user', v_user_id,
      'platform_user_id', v_platform_user_id
    )
  );

  RETURN to_jsonb(v_order);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.client_confirm_pickup_v2(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.client_confirm_pickup_v2(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.client_confirm_pickup_v2(UUID, UUID) TO service_role;
COMMIT;
