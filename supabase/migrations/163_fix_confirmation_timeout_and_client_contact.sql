-- Restore correct confirmation windows and expose client contact safely.

CREATE OR REPLACE FUNCTION public.process_restaurant_confirmation_timeouts()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_user_id UUID;
  v_count INTEGER := 0;
BEGIN
  FOR v_order IN
    SELECT o.id, o.client_id, o.customer_id
    FROM public.orders o
    WHERE (
      o.status = 'paid'
      AND COALESCE(o.updated_at, o.created_at) <= NOW() - INTERVAL '3 minutes'
    ) OR (
      o.status = 'pending'
      AND COALESCE(o.payment_status, 'pending') IN ('paid', 'completed')
      AND COALESCE(o.updated_at, o.created_at) <= NOW() - INTERVAL '3 minutes'
    ) OR (
      o.status = 'pending'
      AND COALESCE(o.payment_status, 'pending') NOT IN ('paid', 'completed')
      AND o.created_at <= NOW() - INTERVAL '15 minutes'
    )
  LOOP
    v_user_id := COALESCE(v_order.client_id, v_order.customer_id);
    IF v_user_id IS NULL THEN
      CONTINUE;
    END IF;

    PERFORM public.process_order_cancellation(
      v_order.id,
      v_user_id,
      'restaurant_timeout'
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.process_restaurant_confirmation_timeouts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_restaurant_confirmation_timeouts() TO authenticated, service_role;
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
CREATE OR REPLACE FUNCTION public.get_order_client_contact(
  p_order_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_order RECORD;
  v_client RECORD;
  v_restaurant_owner UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  SELECT o.id,
         o.client_id,
         o.customer_id,
         o.courier_id,
         o.restaurant_id
  INTO v_order
  FROM public.orders o
  WHERE o.id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  SELECT r.owner_id
  INTO v_restaurant_owner
  FROM public.restaurants r
  WHERE r.id = v_order.restaurant_id;

  IF v_user_id <> COALESCE(v_order.client_id, v_user_id)
     AND v_user_id <> COALESCE(v_order.customer_id, v_user_id)
     AND v_user_id <> COALESCE(v_order.courier_id, v_user_id)
     AND v_user_id <> COALESCE(v_restaurant_owner, v_user_id) THEN
    RAISE EXCEPTION 'not_allowed';
  END IF;

  SELECT
    NULLIF(BTRIM(p.full_name), '') AS full_name,
    NULLIF(BTRIM(p.gender), '') AS gender,
    NULLIF(BTRIM(p.phone), '') AS phone
  INTO v_client
  FROM public.profiles p
  WHERE p.id = COALESCE(v_order.client_id, v_order.customer_id);

  RETURN jsonb_build_object(
    'full_name', v_client.full_name,
    'gender', v_client.gender,
    'phone', v_client.phone
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_order_client_contact(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_order_client_contact(UUID) TO authenticated, service_role;
