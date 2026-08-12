BEGIN;
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
       OR v_secret.verified_at IS NOT NULL THEN
      v_otp_code := LPAD(((floor(random() * 9000) + 1000)::INT)::TEXT, 4, '0');
      v_otp_expires_at := v_now + INTERVAL '12 hours';

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
      v_otp_expires_at := GREATEST(
        COALESCE(v_secret.expires_at, v_now),
        v_now + INTERVAL '12 hours'
      );

      UPDATE public.delivery_otp_secrets
      SET expires_at = v_otp_expires_at,
          updated_at = v_now
      WHERE order_id = p_order_id;
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
CREATE OR REPLACE FUNCTION public.request_delivery_otp_regeneration(
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
  v_secret public.delivery_otp_secrets%rowtype;
  v_now TIMESTAMPTZ := NOW();
  v_otp_code TEXT;
  v_otp_expires_at TIMESTAMPTZ;
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

  IF COALESCE(v_order.delivery_type, '') = 'pickup'
     OR COALESCE(v_order.delivery_fee, 0) <= 0 THEN
    RAISE EXCEPTION 'order_not_delivery';
  END IF;

  IF v_order.status NOT IN ('in_transit', 'arrived') THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  SELECT *
  INTO v_secret
  FROM public.delivery_otp_secrets
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF v_secret.order_id IS NULL THEN
    RAISE EXCEPTION 'otp_not_generated';
  END IF;

  IF COALESCE(v_secret.regeneration_count, 0) >= 1 THEN
    RAISE EXCEPTION 'otp_regeneration_limit_reached';
  END IF;

  v_otp_code := LPAD(((floor(random() * 9000) + 1000)::INT)::TEXT, 4, '0');
  v_otp_expires_at := v_now + INTERVAL '12 hours';

  UPDATE public.delivery_otp_secrets
  SET otp_code = v_otp_code,
      expires_at = v_otp_expires_at,
      generated_at = v_now,
      verified_at = NULL,
      regeneration_count = COALESCE(regeneration_count, 0) + 1,
      last_regenerated_at = v_now,
      updated_at = v_now
  WHERE order_id = p_order_id;

  UPDATE public.orders
  SET delivery_otp_expires_at = v_otp_expires_at,
      delivery_otp_generated_at = v_now,
      delivery_otp_verified_at = NULL,
      delivery_otp_regeneration_count = COALESCE(delivery_otp_regeneration_count, 0) + 1,
      updated_at = v_now
  WHERE id = p_order_id;

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
    'delivery_otp_regenerated',
    v_user_id,
    'customer',
    v_order.status,
    v_order.status,
    jsonb_build_object(
      'expires_at', v_otp_expires_at,
      'regeneration_count', COALESCE(v_secret.regeneration_count, 0) + 1
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'status', v_order.status,
    'otp_code', v_otp_code,
    'expires_at', v_otp_expires_at,
    'regeneration_count', COALESCE(v_secret.regeneration_count, 0) + 1
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.request_delivery_otp_regeneration(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_delivery_otp_regeneration(UUID) TO authenticated;
CREATE OR REPLACE FUNCTION public.verify_delivery_otp_service(
  p_order_id UUID,
  p_courier_id UUID,
  p_otp_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%rowtype;
  v_secret public.delivery_otp_secrets%rowtype;
  v_previous_status TEXT;
  v_client_id UUID;
  v_restaurant_owner UUID;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF p_courier_id IS NULL THEN
    RAISE EXCEPTION 'courier_required';
  END IF;

  IF COALESCE(btrim(p_otp_code), '') = '' THEN
    RAISE EXCEPTION 'otp_required';
  END IF;

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF v_order.courier_id IS NULL OR v_order.courier_id <> p_courier_id THEN
    RAISE EXCEPTION 'not_assigned_courier';
  END IF;

  IF COALESCE(v_order.delivery_type, '') = 'pickup'
     OR COALESCE(v_order.delivery_fee, 0) <= 0 THEN
    RAISE EXCEPTION 'order_not_delivery';
  END IF;

  IF v_order.status IN ('completed', 'auto_completed') THEN
    RETURN jsonb_build_object(
      'success', true,
      'duplicate', true,
      'status', v_order.status
    );
  END IF;

  IF v_order.status = 'disputed' THEN
    RAISE EXCEPTION 'order_in_dispute';
  END IF;

  IF v_order.status = 'delivered' THEN
    RETURN jsonb_build_object(
      'success', true,
      'duplicate', true,
      'status', 'delivered',
      'delivered_at', v_order.delivered_at
    );
  END IF;

  IF v_order.status NOT IN ('in_transit', 'arrived') THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  SELECT *
  INTO v_secret
  FROM public.delivery_otp_secrets
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF v_secret.order_id IS NULL THEN
    RAISE EXCEPTION 'otp_not_generated';
  END IF;

  IF v_secret.verified_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'duplicate', true,
      'status', 'delivered',
      'delivered_at', v_order.delivered_at
    );
  END IF;

  IF v_secret.expires_at IS NULL OR v_secret.expires_at <= v_now THEN
    UPDATE public.delivery_otp_secrets
    SET expires_at = v_now + INTERVAL '12 hours',
        updated_at = v_now
    WHERE order_id = p_order_id
    RETURNING * INTO v_secret;

    UPDATE public.orders
    SET delivery_otp_expires_at = v_secret.expires_at,
        updated_at = v_now
    WHERE id = p_order_id;
  END IF;

  IF btrim(p_otp_code) <> v_secret.otp_code THEN
    RAISE EXCEPTION 'invalid_otp';
  END IF;

  v_previous_status := v_order.status;
  v_client_id := COALESCE(v_order.client_id, v_order.customer_id);

  UPDATE public.delivery_otp_secrets
  SET verified_at = v_now,
      updated_at = v_now
  WHERE order_id = p_order_id;

  UPDATE public.orders
  SET status = 'delivered',
      delivered_at = COALESCE(delivered_at, v_now),
      delivery_otp_verified_at = COALESCE(delivery_otp_verified_at, v_now),
      updated_at = v_now
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  UPDATE public.deliveries
  SET status = 'delivered',
      delivered_at = COALESCE(delivered_at, v_now),
      updated_at = v_now
  WHERE order_id = p_order_id;

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
    'delivery_otp_verified_event',
    p_courier_id,
    'courier',
    v_previous_status,
    'delivered',
    jsonb_build_object(
      'verification_method', 'otp',
      'verified_at', v_order.delivery_otp_verified_at
    )
  );

  IF v_client_id IS NOT NULL THEN
    PERFORM public.create_app_notification(
      p_user_id := v_client_id,
      p_type := 'ORDER_DELIVERED',
      p_title := 'Entrega validada com codigo',
      p_body := 'O estafeta confirmou a entrega com o teu codigo. Confirma no app quando receberes tudo.',
      p_action := 'OPEN_ORDER',
      p_entity_id := p_order_id::TEXT,
      p_priority := 'HIGH',
      p_channel := 'delivery',
      p_metadata := jsonb_build_object(
        'order_id', p_order_id,
        'verification_method', 'otp'
      )
    );
  END IF;

  SELECT owner_id
  INTO v_restaurant_owner
  FROM public.restaurants
  WHERE id = v_order.restaurant_id;

  IF v_restaurant_owner IS NOT NULL THEN
    PERFORM public.create_app_notification(
      p_user_id := v_restaurant_owner,
      p_type := 'ORDER_DELIVERED',
      p_title := 'Entrega validada com OTP',
      p_body := 'O estafeta concluiu a entrega e o cliente ainda pode confirmar ou reportar um problema no app.',
      p_action := 'OPEN_ORDER',
      p_entity_id := p_order_id::TEXT,
      p_priority := 'HIGH',
      p_channel := 'restaurant',
      p_metadata := jsonb_build_object(
        'order_id', p_order_id,
        'verification_method', 'otp'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', 'delivered',
    'delivered_at', v_order.delivered_at,
    'delivery_otp_verified_at', v_order.delivery_otp_verified_at
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.verify_delivery_otp_service(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.verify_delivery_otp_service(UUID, UUID, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.verify_delivery_otp_service(UUID, UUID, TEXT) TO service_role;
COMMIT;
