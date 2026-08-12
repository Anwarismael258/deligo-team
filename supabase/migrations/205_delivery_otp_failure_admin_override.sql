BEGIN;
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
  CHECK (
    status IN (
      'pending',
      'paid',
      'payment_authorized',
      'accepted',
      'preparing',
      'ready',
      'awaiting_pickup_confirmation',
      'picked_up',
      'in_delivery',
      'courier_assigned',
      'on_the_way',
      'in_transit',
      'arrived',
      'delivery_failed_otp',
      'delivered',
      'disputed',
      'completed',
      'auto_completed',
      'expired',
      'payment_failed',
      'refunded',
      'cancelled'
    )
  );
CREATE OR REPLACE FUNCTION public.validate_order_transition(
  p_from_status TEXT,
  p_to_status TEXT,
  p_delivery_type TEXT DEFAULT 'delivery'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_from TEXT := LOWER(COALESCE(p_from_status, ''));
  v_to TEXT := LOWER(COALESCE(p_to_status, ''));
  v_delivery_type TEXT := LOWER(COALESCE(p_delivery_type, 'delivery'));
BEGIN
  IF v_from = '' OR v_to = '' THEN
    RETURN FALSE;
  END IF;

  IF v_from = v_to THEN
    RETURN TRUE;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM (
      VALUES
        ('pending', 'payment_authorized', NULL),
        ('pending', 'paid', NULL),
        ('pending', 'payment_failed', NULL),
        ('pending', 'cancelled', NULL),
        ('paid', 'accepted', NULL),
        ('paid', 'expired', NULL),
        ('paid', 'cancelled', NULL),
        ('payment_authorized', 'accepted', NULL),
        ('payment_authorized', 'expired', NULL),
        ('payment_authorized', 'cancelled', NULL),
        ('accepted', 'preparing', NULL),
        ('preparing', 'ready', NULL),
        ('ready', 'awaiting_pickup_confirmation', 'pickup'),
        ('awaiting_pickup_confirmation', 'completed', 'pickup'),
        ('ready', 'completed', 'pickup'),
        ('ready', 'auto_completed', 'pickup'),
        ('ready', 'picked_up', 'delivery'),
        ('picked_up', 'in_delivery', 'delivery'),
        ('in_delivery', 'arrived', 'delivery'),
        ('ready', 'courier_assigned', 'delivery'),
        ('courier_assigned', 'in_transit', 'delivery'),
        ('ready', 'in_transit', 'delivery'),
        ('in_transit', 'arrived', 'delivery'),
        ('in_transit', 'delivery_failed_otp', 'delivery'),
        ('in_transit', 'delivered', 'delivery'),
        ('arrived', 'delivery_failed_otp', 'delivery'),
        ('arrived', 'delivered', 'delivery'),
        ('delivery_failed_otp', 'completed', 'delivery'),
        ('delivery_failed_otp', 'disputed', 'delivery'),
        ('delivered', 'completed', 'delivery'),
        ('delivered', 'auto_completed', 'delivery'),
        ('delivered', 'disputed', 'delivery'),
        ('cancelled', 'refunded', NULL),
        ('expired', 'refunded', NULL)
    ) AS allowed(from_status, to_status, delivery_type)
    WHERE allowed.from_status = v_from
      AND allowed.to_status = v_to
      AND (allowed.delivery_type IS NULL OR allowed.delivery_type = v_delivery_type)
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.order_event_topic(
  p_event_type TEXT,
  p_old_status TEXT DEFAULT NULL,
  p_new_status TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_event_type TEXT := LOWER(COALESCE(btrim(p_event_type), ''));
  v_old_status TEXT := LOWER(COALESCE(btrim(p_old_status), ''));
  v_new_status TEXT := LOWER(COALESCE(btrim(p_new_status), ''));
BEGIN
  IF v_event_type = '' THEN
    RETURN 'ORDER_EVENT_UNKNOWN';
  END IF;

  IF v_event_type = 'status_changed' THEN
    CASE v_new_status
      WHEN 'accepted' THEN RETURN 'ORDER_ACCEPTED';
      WHEN 'preparing' THEN RETURN 'ORDER_PREPARING';
      WHEN 'ready' THEN RETURN 'ORDER_READY';
      WHEN 'courier_assigned' THEN RETURN 'COURIER_ASSIGNED';
      WHEN 'in_transit' THEN RETURN 'ORDER_PICKED_UP';
      WHEN 'arrived' THEN RETURN 'ORDER_ARRIVED';
      WHEN 'delivery_failed_otp' THEN RETURN 'DELIVERY_OTP_FAILED';
      WHEN 'delivered' THEN RETURN 'ORDER_DELIVERED';
      WHEN 'completed' THEN RETURN 'ORDER_COMPLETED';
      WHEN 'auto_completed' THEN RETURN 'ORDER_AUTO_COMPLETED';
      WHEN 'cancelled' THEN RETURN 'ORDER_CANCELLED';
      WHEN 'expired' THEN RETURN 'ORDER_EXPIRED';
      WHEN 'disputed' THEN RETURN 'ORDER_DISPUTED';
      ELSE
        RETURN 'ORDER_STATUS_' || UPPER(REPLACE(COALESCE(v_new_status, 'unknown'), ' ', '_'));
    END CASE;
  END IF;

  CASE v_event_type
    WHEN 'order_created' THEN RETURN 'ORDER_CREATED';
    WHEN 'courier_assigned' THEN RETURN 'COURIER_ASSIGNED';
    WHEN 'courier_changed' THEN RETURN 'COURIER_CHANGED';
    WHEN 'courier_unassigned' THEN RETURN 'COURIER_UNASSIGNED';
    WHEN 'pickup_confirmed_by_customer' THEN RETURN 'ORDER_COMPLETED';
    WHEN 'pickup_auto_completed' THEN RETURN 'ORDER_AUTO_COMPLETED';
    WHEN 'delivery_auto_completed' THEN RETURN 'ORDER_AUTO_COMPLETED';
    WHEN 'delivery_problem_reported' THEN RETURN 'ORDER_DISPUTED';
    WHEN 'delivery_extension_requested' THEN RETURN 'DELIVERY_EXTENSION_REQUESTED';
    WHEN 'delivery_otp_issued' THEN RETURN 'DELIVERY_OTP_ISSUED';
    WHEN 'delivery_otp_regenerated' THEN RETURN 'DELIVERY_OTP_REGENERATED';
    WHEN 'delivery_otp_failed' THEN RETURN 'DELIVERY_OTP_FAILED_AUDIT';
    WHEN 'delivery_otp_verified_event' THEN RETURN 'ORDER_DELIVERED';
    WHEN 'delivery_override_completed' THEN RETURN 'DELIVERY_OVERRIDE_COMPLETED';
    WHEN 'delivery_override_disputed' THEN RETURN 'DELIVERY_OVERRIDE_DISPUTED';
    WHEN 'payment_confirmed' THEN RETURN 'PAYMENT_CONFIRMED';
    WHEN 'payment_failed' THEN RETURN 'PAYMENT_FAILED';
    WHEN 'settlement_processed' THEN RETURN 'PAYMENT_RELEASED';
    WHEN 'refund_issued' THEN RETURN 'REFUND_INITIATED';
    WHEN 'refund_completed' THEN RETURN 'REFUND_COMPLETED';
    WHEN 'restaurant_timeout_cancel_failed' THEN RETURN 'ORDER_TIMEOUT_CANCEL_FAILED';
    WHEN 'pickup_auto_complete_failed' THEN RETURN 'ORDER_AUTO_COMPLETE_FAILED';
    WHEN 'delivery_auto_complete_failed' THEN RETURN 'ORDER_AUTO_COMPLETE_FAILED';
    WHEN 'courier_reassignment_requested' THEN RETURN 'COURIER_REASSIGNMENT_REQUESTED';
    WHEN 'delivery_sla_exceeded' THEN RETURN 'DELIVERY_SLA_EXCEEDED';
    ELSE
      RETURN UPPER(REGEXP_REPLACE(v_event_type, '[^a-z0-9]+', '_', 'g'));
  END CASE;
END;
$$;
CREATE TABLE IF NOT EXISTS public.delivery_override_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  admin_id UUID NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  courier_id UUID NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  reason TEXT NOT NULL,
  notes TEXT NULL,
  proof_type TEXT NOT NULL,
  proof_url TEXT NULL,
  gps_latitude NUMERIC(10,8) NULL,
  gps_longitude NUMERIC(11,8) NULL,
  call_attempted BOOLEAN NOT NULL DEFAULT FALSE,
  outcome TEXT NOT NULL DEFAULT 'completed',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.delivery_override_logs
  DROP CONSTRAINT IF EXISTS delivery_override_logs_reason_check;
ALTER TABLE public.delivery_override_logs
  ADD CONSTRAINT delivery_override_logs_reason_check
  CHECK (
    reason IN (
      'customer_unreachable',
      'otp_failed',
      'device_issue',
      'customer_requested_manual'
    )
  );
ALTER TABLE public.delivery_override_logs
  DROP CONSTRAINT IF EXISTS delivery_override_logs_proof_type_check;
ALTER TABLE public.delivery_override_logs
  ADD CONSTRAINT delivery_override_logs_proof_type_check
  CHECK (proof_type IN ('photo', 'gps', 'call'));
ALTER TABLE public.delivery_override_logs
  DROP CONSTRAINT IF EXISTS delivery_override_logs_outcome_check;
ALTER TABLE public.delivery_override_logs
  ADD CONSTRAINT delivery_override_logs_outcome_check
  CHECK (outcome IN ('completed', 'disputed'));
CREATE INDEX IF NOT EXISTS idx_delivery_override_logs_order_created_at
  ON public.delivery_override_logs(order_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_delivery_override_logs_admin_created_at
  ON public.delivery_override_logs(admin_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_delivery_override_logs_courier_created_at
  ON public.delivery_override_logs(courier_id, created_at DESC);
ALTER TABLE public.delivery_override_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS delivery_override_logs_select_admin ON public.delivery_override_logs;
CREATE POLICY delivery_override_logs_select_admin
ON public.delivery_override_logs
FOR SELECT TO authenticated
USING (public.is_admin());
DROP POLICY IF EXISTS delivery_override_logs_insert_admin ON public.delivery_override_logs;
CREATE POLICY delivery_override_logs_insert_admin
ON public.delivery_override_logs
FOR INSERT TO authenticated
WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS delivery_override_logs_service_all ON public.delivery_override_logs;
CREATE POLICY delivery_override_logs_service_all
ON public.delivery_override_logs
FOR ALL TO service_role
USING (true)
WITH CHECK (true);
CREATE OR REPLACE FUNCTION public.courier_mark_delivery_otp_failed(
  p_order_id UUID,
  p_reason TEXT DEFAULT 'otp_failed',
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_courier_id UUID := auth.uid();
  v_order public.orders%rowtype;
  v_previous_status TEXT;
  v_admin RECORD;
  v_normalized_reason TEXT := LOWER(COALESCE(NULLIF(btrim(p_reason), ''), 'otp_failed'));
  v_order_ref TEXT;
BEGIN
  IF v_courier_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  IF v_normalized_reason NOT IN (
    'customer_unreachable',
    'otp_failed',
    'device_issue',
    'customer_requested_manual'
  ) THEN
    RAISE EXCEPTION 'invalid_override_reason';
  END IF;

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF v_order.courier_id IS NULL OR v_order.courier_id <> v_courier_id THEN
    RAISE EXCEPTION 'not_assigned_courier';
  END IF;

  IF COALESCE(v_order.delivery_type, '') = 'pickup'
     OR COALESCE(v_order.delivery_fee, 0) <= 0 THEN
    RAISE EXCEPTION 'order_not_delivery';
  END IF;

  IF v_order.status = 'delivery_failed_otp' THEN
    RETURN jsonb_build_object(
      'success', true,
      'duplicate', true,
      'status', v_order.status
    );
  END IF;

  IF v_order.status IN ('completed', 'auto_completed', 'disputed', 'delivered') THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  IF v_order.status NOT IN ('in_transit', 'arrived') THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  v_previous_status := v_order.status;
  v_order_ref := '#' || UPPER(LEFT(REPLACE(v_order.id::TEXT, '-', ''), 6));

  UPDATE public.orders
  SET status = 'delivery_failed_otp',
      updated_at = NOW()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  UPDATE public.deliveries
  SET status = 'delivery_failed_otp',
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
    'delivery_otp_failed',
    v_courier_id,
    'courier',
    v_previous_status,
    'delivery_failed_otp',
    jsonb_build_object(
      'reason', v_normalized_reason,
      'notes', NULLIF(btrim(COALESCE(p_notes, '')), ''),
      'source', 'courier_mark_delivery_otp_failed'
    )
  );

  FOR v_admin IN
    SELECT id
    FROM public.profiles
    WHERE role = 'admin'
      AND COALESCE(is_blocked, false) = false
  LOOP
    PERFORM public.create_app_notification(
      p_user_id := v_admin.id,
      p_type := 'SUPPORT_UPDATED',
      p_title := 'Entrega com falha no OTP',
      p_body := 'O pedido ' || v_order_ref || ' precisa de revisao admin porque o OTP falhou na entrega.',
      p_action := 'OPEN_ORDER',
      p_entity_id := p_order_id::TEXT,
      p_priority := 'HIGH',
      p_channel := 'support',
      p_metadata := jsonb_build_object(
        'order_id', p_order_id,
        'status', 'delivery_failed_otp',
        'reason', v_normalized_reason,
        'courier_id', v_courier_id
      )
    );
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'status', v_order.status,
    'reason', v_normalized_reason
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.courier_mark_delivery_otp_failed(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.courier_mark_delivery_otp_failed(UUID, TEXT, TEXT) TO authenticated;
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
    AND created_at >= NOW() - INTERVAL '1 day';

  IF v_today_override_count >= 25 THEN
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
REVOKE EXECUTE ON FUNCTION public.admin_override_delivery_after_failed_otp(UUID, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, BOOLEAN, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_override_delivery_after_failed_otp(UUID, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, BOOLEAN, BOOLEAN) TO authenticated;
COMMIT;
