BEGIN;
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
  v_otp_expires_at := v_now + INTERVAL '30 minutes';

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
CREATE OR REPLACE FUNCTION public.client_request_delivery_extension(
  p_order_id UUID,
  p_extra_minutes INTEGER DEFAULT 10
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_order public.orders%rowtype;
  v_now TIMESTAMPTZ := NOW();
  v_deadline TIMESTAMPTZ;
  v_new_deadline TIMESTAMPTZ;
  v_courier_id UUID;
  v_extra_minutes INTEGER := LEAST(GREATEST(COALESCE(p_extra_minutes, 10), 1), 30);
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

  IF v_order.status <> 'delivered' THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  IF COALESCE(v_order.delivery_extension_count, 0) >= 1 THEN
    RAISE EXCEPTION 'delivery_extension_limit_reached';
  END IF;

  v_deadline := COALESCE(
    v_order.delivery_extension_until,
    COALESCE(v_order.delivered_at, v_order.updated_at, v_order.created_at) + INTERVAL '10 minutes'
  );

  IF v_deadline <= v_now THEN
    RAISE EXCEPTION 'delivery_extension_window_closed';
  END IF;

  v_new_deadline := v_deadline + make_interval(mins => v_extra_minutes);

  UPDATE public.orders
  SET delivery_extension_until = v_new_deadline,
      delivery_extension_count = COALESCE(delivery_extension_count, 0) + 1,
      updated_at = v_now
  WHERE id = p_order_id
  RETURNING courier_id INTO v_courier_id;

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
    'delivery_extension_requested',
    v_user_id,
    'customer',
    v_order.status,
    v_order.status,
    jsonb_build_object(
      'extra_minutes', v_extra_minutes,
      'new_deadline', v_new_deadline
    )
  );

  IF v_courier_id IS NOT NULL THEN
    PERFORM public.create_app_notification(
      p_user_id := v_courier_id,
      p_type := 'DELIVERY_EXTENSION_REQUESTED',
      p_title := 'Cliente pediu mais tempo',
      p_body := 'O cliente pediu mais 10 minutos antes do fecho automatico desta entrega.',
      p_action := 'OPEN_ORDER',
      p_entity_id := p_order_id::TEXT,
      p_priority := 'HIGH',
      p_channel := 'delivery',
      p_metadata := jsonb_build_object(
        'order_id', p_order_id,
        'new_deadline', v_new_deadline
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', 'delivered',
    'delivery_extension_until', v_new_deadline
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.client_request_delivery_extension(UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.client_request_delivery_extension(UUID, INTEGER) TO authenticated;
CREATE OR REPLACE FUNCTION public.client_report_delivery_problem(
  p_order_id UUID,
  p_reason TEXT,
  p_dispute_type TEXT DEFAULT 'delivery_issue'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_order public.orders%rowtype;
  v_dispute JSONB;
  v_existing_dispute_id UUID;
  v_deadline TIMESTAMPTZ;
  v_admin RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  IF COALESCE(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'reason_required';
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

  IF v_order.status NOT IN ('delivered', 'disputed') THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  v_deadline := COALESCE(
    v_order.delivery_extension_until,
    COALESCE(v_order.delivered_at, v_order.updated_at, v_order.created_at) + INTERVAL '10 minutes'
  );

  IF v_deadline <= NOW() THEN
    RAISE EXCEPTION 'delivery_dispute_window_closed';
  END IF;

  SELECT od.id
  INTO v_existing_dispute_id
  FROM public.order_disputes od
  WHERE od.order_id = p_order_id
    AND COALESCE(od.status, 'open') = 'open'
  ORDER BY od.created_at DESC
  LIMIT 1;

  IF v_existing_dispute_id IS NULL THEN
    v_dispute := public.open_order_dispute(
      p_order_id := p_order_id,
      p_opened_by := v_user_id,
      p_opened_by_role := 'customer',
      p_dispute_type := COALESCE(NULLIF(btrim(p_dispute_type), ''), 'delivery_issue'),
      p_reason := p_reason,
      p_metadata := jsonb_build_object(
        'source', 'client_report_delivery_problem',
        'reported_before_auto_close', true
      )
    );
    v_existing_dispute_id := (v_dispute ->> 'dispute_id')::UUID;
  END IF;

  UPDATE public.orders
  SET status = 'disputed',
      dispute_reason = p_reason,
      dispute_created_at = COALESCE(dispute_created_at, NOW()),
      updated_at = NOW()
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
    'delivery_problem_reported',
    v_user_id,
    'customer',
    v_order.status,
    'disputed',
    jsonb_build_object(
      'dispute_id', v_existing_dispute_id,
      'reason', p_reason
    )
  );

  FOR v_admin IN
    SELECT id
    FROM public.profiles
    WHERE role = 'admin'
  LOOP
    PERFORM public.create_app_notification(
      p_user_id := v_admin.id,
      p_type := 'SUPPORT_UPDATED',
      p_title := 'Nova disputa de entrega',
      p_body := 'Uma entrega foi marcada com problema antes do fecho automatico.',
      p_action := 'OPEN_SUPPORT',
      p_entity_id := p_order_id::TEXT,
      p_priority := 'HIGH',
      p_channel := 'support',
      p_metadata := jsonb_build_object(
        'order_id', p_order_id,
        'dispute_id', v_existing_dispute_id,
        'reason', p_reason,
        'status', 'disputed'
      )
    );
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'status', 'disputed',
    'dispute_id', v_existing_dispute_id
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.client_report_delivery_problem(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.client_report_delivery_problem(UUID, TEXT, TEXT) TO authenticated;
COMMIT;
