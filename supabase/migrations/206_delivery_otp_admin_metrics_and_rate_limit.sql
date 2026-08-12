BEGIN;
CREATE OR REPLACE FUNCTION public.admin_override_delivery_after_failed_otp(
  p_order_id UUID,
  p_reason TEXT,
  p_notes TEXT DEFAULT NULL,
  p_proof_type TEXT DEFAULT NULL,
  p_proof_url TEXT DEFAULT NULL,
  p_gps_latitude NUMERIC DEFAULT NULL,
  p_gps_longitude NUMERIC DEFAULT NULL,
  p_call_attempted BOOLEAN DEFAULT FALSE,
  p_mark_as_disputed BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_order public.orders%rowtype;
  v_delivery public.deliveries%rowtype;
  v_customer_id UUID;
  v_previous_status TEXT;
  v_normalized_reason TEXT := LOWER(COALESCE(NULLIF(btrim(p_reason), ''), 'otp_failed'));
  v_normalized_proof_type TEXT := LOWER(COALESCE(NULLIF(btrim(p_proof_type), ''), ''));
  v_notes TEXT := NULLIF(btrim(COALESCE(p_notes, '')), '');
  v_effective_photo_url TEXT;
  v_effective_gps_latitude NUMERIC;
  v_effective_gps_longitude NUMERIC;
  v_today_override_count INTEGER := 0;
  v_courier_override_count INTEGER := 0;
  v_platform_user_id UUID;
  v_result JSONB := '{}'::jsonb;
  v_dispute JSONB := '{}'::jsonb;
  v_dispute_id UUID;
  v_log_id UUID;
BEGIN
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF v_normalized_reason NOT IN (
    'customer_unreachable',
    'otp_failed',
    'device_issue',
    'customer_requested_manual'
  ) THEN
    RAISE EXCEPTION 'invalid_override_reason';
  END IF;

  IF v_normalized_proof_type NOT IN ('photo', 'gps', 'call') THEN
    RAISE EXCEPTION 'proof_required';
  END IF;

  SELECT COUNT(*)
  INTO v_today_override_count
  FROM public.delivery_override_logs
  WHERE admin_id = v_admin_id
    AND timezone('Africa/Johannesburg', created_at)::date =
        timezone('Africa/Johannesburg', NOW())::date;

  IF v_today_override_count >= 20 THEN
    RAISE EXCEPTION 'admin_override_rate_limit_reached';
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

  IF v_order.status <> 'delivery_failed_otp' THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  IF v_order.courier_id IS NULL THEN
    RAISE EXCEPTION 'courier_required';
  END IF;

  SELECT *
  INTO v_delivery
  FROM public.deliveries
  WHERE order_id = p_order_id
  FOR UPDATE;

  v_effective_photo_url := COALESCE(
    NULLIF(btrim(COALESCE(p_proof_url, '')), ''),
    NULLIF(btrim(COALESCE(v_delivery.proof_photo_url, '')), '')
  );
  v_effective_gps_latitude := COALESCE(
    p_gps_latitude,
    v_delivery.proof_latitude,
    v_delivery.current_latitude
  );
  v_effective_gps_longitude := COALESCE(
    p_gps_longitude,
    v_delivery.proof_longitude,
    v_delivery.current_longitude
  );

  IF v_normalized_proof_type = 'photo' AND v_effective_photo_url IS NULL THEN
    RAISE EXCEPTION 'photo_proof_required';
  END IF;

  IF v_normalized_proof_type = 'gps'
     AND (v_effective_gps_latitude IS NULL OR v_effective_gps_longitude IS NULL) THEN
    RAISE EXCEPTION 'gps_proof_required';
  END IF;

  IF v_normalized_proof_type = 'call' AND COALESCE(p_call_attempted, false) = false THEN
    RAISE EXCEPTION 'call_proof_required';
  END IF;

  SELECT COUNT(*)
  INTO v_courier_override_count
  FROM public.delivery_override_logs
  WHERE courier_id = v_order.courier_id
    AND created_at >= NOW() - INTERVAL '30 days';

  v_previous_status := v_order.status;
  v_customer_id := COALESCE(v_order.client_id, v_order.customer_id);
  v_platform_user_id := COALESCE(
    (SELECT id FROM public.profiles WHERE id = '2ef7f269-b36e-4903-ab2d-72b2a74ca28e'::uuid LIMIT 1),
    (SELECT id FROM public.profiles WHERE role = 'admin' ORDER BY created_at ASC LIMIT 1)
  );

  INSERT INTO public.delivery_override_logs (
    order_id,
    admin_id,
    courier_id,
    reason,
    notes,
    proof_type,
    proof_url,
    gps_latitude,
    gps_longitude,
    call_attempted,
    outcome,
    metadata
  ) VALUES (
    p_order_id,
    v_admin_id,
    v_order.courier_id,
    v_normalized_reason,
    v_notes,
    v_normalized_proof_type,
    v_effective_photo_url,
    v_effective_gps_latitude,
    v_effective_gps_longitude,
    COALESCE(p_call_attempted, false),
    CASE WHEN p_mark_as_disputed THEN 'disputed' ELSE 'completed' END,
    jsonb_build_object(
      'source', 'admin_override_delivery_after_failed_otp',
      'previous_status', v_previous_status,
      'courier_override_count_30d', v_courier_override_count + 1
    )
  )
  RETURNING id INTO v_log_id;

  IF p_mark_as_disputed THEN
    v_dispute := public.open_order_dispute(
      p_order_id := p_order_id,
      p_opened_by := v_admin_id,
      p_opened_by_role := 'admin',
      p_dispute_type := 'delivery_otp_failure',
      p_reason := COALESCE(v_notes, 'Entrega com OTP falhado enviada para disputa administrativa.'),
      p_metadata := jsonb_build_object(
        'source', 'admin_override_delivery_after_failed_otp',
        'override_log_id', v_log_id,
        'proof_type', v_normalized_proof_type
      )
    );
    v_dispute_id := NULLIF(v_dispute ->> 'dispute_id', '')::UUID;

    UPDATE public.orders
    SET status = 'disputed',
        dispute_reason = COALESCE(v_notes, 'Entrega com OTP falhado enviada para disputa administrativa.'),
        dispute_created_at = COALESCE(dispute_created_at, NOW()),
        updated_at = NOW()
    WHERE id = p_order_id
    RETURNING * INTO v_order;

    UPDATE public.deliveries
    SET status = 'disputed',
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
      'delivery_override_disputed',
      v_admin_id,
      'admin',
      v_previous_status,
      'disputed',
      jsonb_build_object(
        'override_log_id', v_log_id,
        'proof_type', v_normalized_proof_type,
        'reason', v_normalized_reason,
        'dispute_id', v_dispute_id
      )
    );

    INSERT INTO public.admin_actions_log (
      admin_id,
      user_id,
      action,
      reason,
      metadata
    ) VALUES (
      v_admin_id,
      v_order.courier_id,
      'delivery_otp_override_disputed',
      COALESCE(v_notes, v_normalized_reason),
      jsonb_build_object(
        'order_id', p_order_id,
        'override_log_id', v_log_id,
        'proof_type', v_normalized_proof_type,
        'dispute_id', v_dispute_id
      )
    );

    RETURN jsonb_build_object(
      'success', true,
      'status', 'disputed',
      'override_log_id', v_log_id,
      'dispute_id', v_dispute_id
    );
  END IF;

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'customer_required';
  END IF;

  UPDATE public.orders
  SET status = 'arrived',
      updated_at = NOW()
  WHERE id = p_order_id
    AND status = 'delivery_failed_otp';

  BEGIN
    v_result := public.process_delivery_settlement(
      p_order_id := p_order_id,
      p_customer_id := v_customer_id,
      p_platform_user_id := v_platform_user_id
    );
  EXCEPTION WHEN OTHERS THEN
    UPDATE public.orders
    SET status = 'delivery_failed_otp',
        updated_at = NOW()
    WHERE id = p_order_id;
    RAISE;
  END;

  UPDATE public.orders
  SET status = 'completed',
      confirmed_by_customer = FALSE,
      delivered_at = COALESCE(delivered_at, NOW()),
      order_completed_at = COALESCE(order_completed_at, NOW()),
      settlement_processed_at = COALESCE(settlement_processed_at, NOW()),
      updated_at = NOW()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  UPDATE public.deliveries
  SET status = 'completed',
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
    'delivery_override_completed',
    v_admin_id,
    'admin',
    v_previous_status,
    'completed',
    jsonb_build_object(
      'override_log_id', v_log_id,
      'proof_type', v_normalized_proof_type,
      'reason', v_normalized_reason,
      'settlement', COALESCE(v_result, '{}'::jsonb)
    )
  );

  INSERT INTO public.admin_actions_log (
    admin_id,
    user_id,
    action,
    reason,
    metadata
  ) VALUES (
    v_admin_id,
    v_order.courier_id,
    'delivery_otp_override_completed',
    COALESCE(v_notes, v_normalized_reason),
    jsonb_build_object(
      'order_id', p_order_id,
      'override_log_id', v_log_id,
      'proof_type', v_normalized_proof_type,
      'settlement', COALESCE(v_result, '{}'::jsonb)
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'status', 'completed',
    'override_log_id', v_log_id,
    'settlement', COALESCE(v_result, '{}'::jsonb)
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.get_delivery_otp_override_summary()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today DATE := timezone('Africa/Johannesburg', NOW())::date;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  RETURN (
    WITH failures AS (
      SELECT COUNT(DISTINCT oe.order_id) AS otp_failed_today
      FROM public.order_events oe
      WHERE oe.event_type = 'delivery_otp_failed'
        AND timezone('Africa/Johannesburg', oe.created_at)::date = v_today
    ),
    overrides AS (
      SELECT
        COUNT(*) AS overrides_today,
        COUNT(*) FILTER (WHERE outcome = 'disputed') AS disputed_overrides_today,
        COUNT(DISTINCT courier_id) AS couriers_with_override_today
      FROM public.delivery_override_logs dol
      WHERE timezone('Africa/Johannesburg', dol.created_at)::date = v_today
    )
    SELECT jsonb_build_object(
      'date', v_today,
      'otp_failed_today', COALESCE(f.otp_failed_today, 0),
      'overrides_today', COALESCE(o.overrides_today, 0),
      'disputed_overrides_today', COALESCE(o.disputed_overrides_today, 0),
      'couriers_with_override_today', COALESCE(o.couriers_with_override_today, 0)
    )
    FROM failures f
    CROSS JOIN overrides o
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_delivery_otp_override_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_delivery_otp_override_summary() TO authenticated;
CREATE OR REPLACE FUNCTION public.get_courier_delivery_otp_risk_metrics(
  p_limit INTEGER DEFAULT 8
)
RETURNS TABLE (
  courier_id UUID,
  courier_name TEXT,
  delivery_orders_30d BIGINT,
  otp_failures_30d BIGINT,
  overrides_30d BIGINT,
  completed_overrides_30d BIGINT,
  disputed_overrides_30d BIGINT,
  otp_failure_rate_30d NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  RETURN QUERY
  WITH delivery_orders AS (
    SELECT
      o.courier_id,
      COUNT(*)::BIGINT AS delivery_orders_30d
    FROM public.orders o
    WHERE o.courier_id IS NOT NULL
      AND COALESCE(
            NULLIF(o.delivery_type, ''),
            CASE WHEN COALESCE(o.delivery_fee, 0) > 0 THEN 'delivery' ELSE 'pickup' END
          ) = 'delivery'
      AND o.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY o.courier_id
  ),
  otp_failures AS (
    SELECT
      oe.actor_id AS courier_id,
      COUNT(DISTINCT oe.order_id)::BIGINT AS otp_failures_30d
    FROM public.order_events oe
    WHERE oe.event_type = 'delivery_otp_failed'
      AND oe.actor_role = 'courier'
      AND oe.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY oe.actor_id
  ),
  overrides AS (
    SELECT
      dol.courier_id,
      COUNT(*)::BIGINT AS overrides_30d,
      COUNT(*) FILTER (WHERE dol.outcome = 'completed')::BIGINT AS completed_overrides_30d,
      COUNT(*) FILTER (WHERE dol.outcome = 'disputed')::BIGINT AS disputed_overrides_30d
    FROM public.delivery_override_logs dol
    WHERE dol.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY dol.courier_id
  ),
  candidates AS (
    SELECT courier_id FROM delivery_orders
    UNION
    SELECT courier_id FROM otp_failures
    UNION
    SELECT courier_id FROM overrides
  )
  SELECT
    c.courier_id,
    COALESCE(NULLIF(btrim(p.full_name), ''), 'Estafeta') AS courier_name,
    COALESCE(d.delivery_orders_30d, 0) AS delivery_orders_30d,
    COALESCE(f.otp_failures_30d, 0) AS otp_failures_30d,
    COALESCE(o.overrides_30d, 0) AS overrides_30d,
    COALESCE(o.completed_overrides_30d, 0) AS completed_overrides_30d,
    COALESCE(o.disputed_overrides_30d, 0) AS disputed_overrides_30d,
    CASE
      WHEN COALESCE(d.delivery_orders_30d, 0) <= 0 THEN 0
      ELSE ROUND(
        (COALESCE(f.otp_failures_30d, 0)::NUMERIC / d.delivery_orders_30d::NUMERIC) * 100,
        2
      )
    END AS otp_failure_rate_30d
  FROM candidates c
  LEFT JOIN public.profiles p
    ON p.id = c.courier_id
  LEFT JOIN delivery_orders d
    ON d.courier_id = c.courier_id
  LEFT JOIN otp_failures f
    ON f.courier_id = c.courier_id
  LEFT JOIN overrides o
    ON o.courier_id = c.courier_id
  WHERE COALESCE(f.otp_failures_30d, 0) > 0
     OR COALESCE(o.overrides_30d, 0) > 0
  ORDER BY
    COALESCE(o.overrides_30d, 0) DESC,
    COALESCE(f.otp_failures_30d, 0) DESC,
    otp_failure_rate_30d DESC,
    COALESCE(d.delivery_orders_30d, 0) DESC
  LIMIT GREATEST(COALESCE(p_limit, 8), 1);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_courier_delivery_otp_risk_metrics(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_courier_delivery_otp_risk_metrics(INTEGER) TO authenticated;
COMMIT;
