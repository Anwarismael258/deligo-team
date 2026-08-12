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

  IF v_order.status IN ('completed', 'auto_completed', 'delivered') THEN
    RETURN to_jsonb(v_order);
  END IF;

  IF v_order.status <> 'ready' THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  PERFORM public.process_delivery_settlement(
    p_order_id := p_order_id,
    p_customer_id := v_user_id,
    p_platform_user_id := NULL
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
    jsonb_build_object('source', 'client_confirm_pickup')
  );

  RETURN to_jsonb(v_order);
END;
$$;
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
  v_previous_status TEXT;
  v_now TIMESTAMPTZ := NOW();
  v_otp_code TEXT;
  v_otp_expires_at TIMESTAMPTZ;
  v_secret RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  IF p_status IS NULL OR btrim(p_status) = '' THEN
    RAISE EXCEPTION 'status_required';
  END IF;

  IF p_status NOT IN ('arrived', 'in_transit') THEN
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
     AND v_order.status NOT IN ('courier_assigned', 'accepted', 'ready', 'in_transit') THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  IF p_status = 'in_transit'
     AND v_order.status NOT IN ('courier_assigned', 'ready', 'arrived') THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  v_previous_status := v_order.status;

  IF p_status = 'in_transit' THEN
    SELECT *
    INTO v_secret
    FROM public.delivery_otp_secrets
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF v_secret.order_id IS NULL
       OR v_secret.verified_at IS NOT NULL
       OR v_secret.expires_at <= v_now THEN
      v_otp_code := LPAD(((floor(random() * 9000) + 1000)::INT)::TEXT, 4, '0');
      v_otp_expires_at := v_now + INTERVAL '30 minutes';

      INSERT INTO public.delivery_otp_secrets (
        order_id,
        otp_code,
        expires_at,
        generated_at,
        verified_at,
        regeneration_count,
        last_regenerated_at,
        updated_at
      ) VALUES (
        p_order_id,
        v_otp_code,
        v_otp_expires_at,
        v_now,
        NULL,
        0,
        NULL,
        v_now
      )
      ON CONFLICT (order_id) DO UPDATE
      SET otp_code = EXCLUDED.otp_code,
          expires_at = EXCLUDED.expires_at,
          generated_at = EXCLUDED.generated_at,
          verified_at = NULL,
          updated_at = EXCLUDED.updated_at;

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
        'delivery_otp_issued',
        v_user_id,
        'courier',
        v_previous_status,
        p_status,
        jsonb_build_object(
          'expires_at', v_otp_expires_at,
          'source', 'courier_update_order_status'
        )
      );
    ELSE
      v_otp_expires_at := v_secret.expires_at;
    END IF;
  END IF;

  UPDATE public.orders
  SET status = p_status,
      picked_up_at = CASE WHEN p_status = 'in_transit' THEN COALESCE(picked_up_at, v_now) ELSE picked_up_at END,
      delivery_otp_generated_at = CASE WHEN p_status = 'in_transit' THEN COALESCE(delivery_otp_generated_at, v_now) ELSE delivery_otp_generated_at END,
      delivery_otp_expires_at = CASE WHEN p_status = 'in_transit' THEN COALESCE(v_otp_expires_at, delivery_otp_expires_at) ELSE delivery_otp_expires_at END,
      updated_at = v_now
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order.id,
    'status', v_order.status,
    'updated_at', v_order.updated_at,
    'picked_up_at', v_order.picked_up_at,
    'delivery_otp_expires_at', v_order.delivery_otp_expires_at
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.courier_update_order_status(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.courier_update_order_status(UUID, TEXT) TO authenticated;
COMMIT;
