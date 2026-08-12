BEGIN;
ALTER TABLE IF EXISTS public.push_notifications
  ADD COLUMN IF NOT EXISTS app_delivered_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS opened_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_ack_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS delivery_ack_payload JSONB NOT NULL DEFAULT '{}'::jsonb;
CREATE INDEX IF NOT EXISTS idx_push_notifications_app_delivered_at
  ON public.push_notifications(app_delivered_at);
CREATE INDEX IF NOT EXISTS idx_push_notifications_opened_at
  ON public.push_notifications(opened_at);
CREATE OR REPLACE FUNCTION public.ack_push_notification_delivery(
  p_notification_id UUID,
  p_state TEXT DEFAULT 'delivered',
  p_context JSONB DEFAULT '{}'::jsonb
)
RETURNS public.push_notifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_state TEXT := lower(COALESCE(NULLIF(btrim(p_state), ''), 'delivered'));
  v_row public.push_notifications%ROWTYPE;
BEGIN
  IF p_notification_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF v_state NOT IN ('delivered', 'opened') THEN
    v_state := 'delivered';
  END IF;

  UPDATE public.push_notifications
  SET
    app_delivered_at = CASE
      WHEN v_state IN ('delivered', 'opened') THEN COALESCE(app_delivered_at, NOW())
      ELSE app_delivered_at
    END,
    opened_at = CASE
      WHEN v_state = 'opened' THEN COALESCE(opened_at, NOW())
      ELSE opened_at
    END,
    read_at = CASE
      WHEN v_state = 'opened' THEN COALESCE(read_at, NOW())
      ELSE read_at
    END,
    delivery_ack_count = COALESCE(delivery_ack_count, 0) + 1,
    delivery_ack_payload = COALESCE(delivery_ack_payload, '{}'::jsonb)
      || jsonb_build_object(
        'last_state', v_state,
        'last_ack_at', NOW(),
        'last_ack_user_id', COALESCE(v_user_id::text, '')
      )
      || COALESCE(p_context, '{}'::jsonb)
  WHERE id = p_notification_id
    AND (
      ((v_user_id IS NOT NULL) AND user_id = v_user_id)
      OR public.is_admin()
    )
  RETURNING * INTO v_row;

  IF v_row.id IS NOT NULL THEN
    PERFORM public.mark_order_event_dispatch_acknowledged(
      p_notification_id := v_row.id,
      p_acknowledged_at := COALESCE(v_row.opened_at, v_row.app_delivered_at, NOW()),
      p_ack_payload := COALESCE(v_row.delivery_ack_payload, '{}'::jsonb)
    );
  END IF;

  RETURN v_row;
END;
$$;
CREATE OR REPLACE FUNCTION public.timeout_waiting_order_event_dispatch_job(
  p_job_id UUID,
  p_error_text TEXT DEFAULT 'ack_timeout'
)
RETURNS public.order_event_dispatch_jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.order_event_dispatch_jobs%ROWTYPE;
  v_notification public.push_notifications%ROWTYPE;
BEGIN
  SELECT *
  INTO v_job
  FROM public.order_event_dispatch_jobs
  WHERE id = p_job_id
  FOR UPDATE;

  IF v_job.id IS NULL THEN
    RAISE EXCEPTION 'dispatch_job_not_found';
  END IF;

  IF v_job.notification_id IS NOT NULL THEN
    SELECT *
    INTO v_notification
    FROM public.push_notifications
    WHERE id = v_job.notification_id
    LIMIT 1;

    IF v_notification.id IS NOT NULL
       AND (
         v_notification.app_delivered_at IS NOT NULL
         OR v_notification.opened_at IS NOT NULL
       ) THEN
      PERFORM public.mark_order_event_dispatch_acknowledged(
        p_notification_id := v_notification.id,
        p_acknowledged_at := COALESCE(v_notification.opened_at, v_notification.app_delivered_at, NOW()),
        p_ack_payload := COALESCE(v_notification.delivery_ack_payload, '{}'::jsonb)
      );

      SELECT *
      INTO v_job
      FROM public.order_event_dispatch_jobs
      WHERE id = p_job_id;

      RETURN v_job;
    END IF;
  END IF;

  UPDATE public.order_event_dispatch_jobs
  SET
    status = CASE
      WHEN COALESCE(retry_count, 0) + 1 >= COALESCE(max_retries, 0) THEN 'dead_letter'
      ELSE 'failed'
    END,
    ack_state = 'timed_out',
    retry_count = COALESCE(retry_count, 0) + 1,
    next_attempt_at = CASE
      WHEN COALESCE(retry_count, 0) + 1 >= COALESCE(max_retries, 0) THEN NULL
      ELSE public.resolve_order_event_dispatch_next_attempt_at(
        COALESCE(payload, '{}'::jsonb),
        COALESCE(retry_count, 0) + 1
      )
    END,
    last_error = COALESCE(p_error_text, last_error, 'ack_timeout'),
    updated_at = NOW(),
    locked_at = NULL,
    locked_by = NULL
  WHERE id = p_job_id
  RETURNING * INTO v_job;

  UPDATE public.order_event_dispatch_attempts
  SET
    status = CASE
      WHEN v_job.status = 'dead_letter' THEN 'dead_letter'
      ELSE 'failed'
    END,
    completed_at = NOW(),
    response_payload = COALESCE(response_payload, '{}'::jsonb)
      || jsonb_build_object(
        'timed_out_at', NOW(),
        'notification_id', COALESCE(v_job.notification_id::text, ''),
        'ack_state', 'timed_out'
      ),
    error_text = COALESCE(p_error_text, error_text, 'ack_timeout')
  WHERE id = (
    SELECT a.id
    FROM public.order_event_dispatch_attempts a
    WHERE a.job_id = p_job_id
      AND a.status = 'sent'
    ORDER BY a.created_at DESC
    LIMIT 1
  );

  RETURN v_job;
END;
$$;
CREATE OR REPLACE FUNCTION public.reset_unacked_order_event_dispatch_jobs(
  p_limit INTEGER DEFAULT 100
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
  v_job RECORD;
BEGIN
  FOR v_job IN
    SELECT j.id
    FROM public.order_event_dispatch_jobs j
    WHERE j.status = 'waiting_ack'
      AND j.ack_state = 'pending'
      AND COALESCE(j.ack_timeout_at, NOW()) <= NOW()
    ORDER BY j.ack_timeout_at NULLS FIRST, j.created_at
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  LOOP
    PERFORM public.timeout_waiting_order_event_dispatch_job(v_job.id, 'ack_timeout');
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.ack_push_notification_delivery(UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ack_push_notification_delivery(UUID, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ack_push_notification_delivery(UUID, TEXT, JSONB) TO service_role;
REVOKE ALL ON FUNCTION public.timeout_waiting_order_event_dispatch_job(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.timeout_waiting_order_event_dispatch_job(UUID, TEXT) TO service_role;
REVOKE ALL ON FUNCTION public.reset_unacked_order_event_dispatch_jobs(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reset_unacked_order_event_dispatch_jobs(INTEGER) TO service_role;
COMMIT;
