BEGIN;
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

  IF v_secret.expires_at <= NOW() THEN
    RAISE EXCEPTION 'otp_expired';
  END IF;

  IF btrim(p_otp_code) <> v_secret.otp_code THEN
    RAISE EXCEPTION 'invalid_otp';
  END IF;

  v_previous_status := v_order.status;
  v_client_id := COALESCE(v_order.client_id, v_order.customer_id);

  UPDATE public.delivery_otp_secrets
  SET verified_at = NOW(),
      updated_at = NOW()
  WHERE order_id = p_order_id;

  UPDATE public.orders
  SET status = 'delivered',
      delivered_at = COALESCE(delivered_at, NOW()),
      delivery_otp_verified_at = COALESCE(delivery_otp_verified_at, NOW()),
      updated_at = NOW()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  UPDATE public.deliveries
  SET status = 'delivered',
      delivered_at = COALESCE(delivered_at, NOW()),
      updated_at = NOW()
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
