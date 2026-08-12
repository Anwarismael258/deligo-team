BEGIN;
ALTER TABLE IF EXISTS public.order_event_dispatch_jobs
  ADD COLUMN IF NOT EXISTS ack_required BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS ack_state TEXT NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS ack_timeout_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ack_latency_ms INTEGER,
  ADD COLUMN IF NOT EXISTS ack_payload JSONB NOT NULL DEFAULT '{}'::jsonb;
CREATE INDEX IF NOT EXISTS idx_order_event_dispatch_jobs_ack_timeout
  ON public.order_event_dispatch_jobs(ack_state, ack_timeout_at, created_at);
ALTER TABLE IF EXISTS public.order_event_dispatch_jobs
  DROP CONSTRAINT IF EXISTS order_event_dispatch_jobs_status_check;
ALTER TABLE IF EXISTS public.order_event_dispatch_jobs
  ADD CONSTRAINT order_event_dispatch_jobs_status_check
  CHECK (status IN ('pending', 'processing', 'waiting_ack', 'sent', 'acked', 'failed', 'skipped', 'dead_letter'));
ALTER TABLE IF EXISTS public.order_event_dispatch_jobs
  DROP CONSTRAINT IF EXISTS order_event_dispatch_jobs_ack_state_check;
ALTER TABLE IF EXISTS public.order_event_dispatch_jobs
  ADD CONSTRAINT order_event_dispatch_jobs_ack_state_check
  CHECK (ack_state IN ('none', 'pending', 'acknowledged', 'timed_out'));
ALTER TABLE IF EXISTS public.order_event_dispatch_attempts
  DROP CONSTRAINT IF EXISTS order_event_dispatch_attempts_status_check;
ALTER TABLE IF EXISTS public.order_event_dispatch_attempts
  ADD CONSTRAINT order_event_dispatch_attempts_status_check
  CHECK (status IN ('processing', 'sent', 'acked', 'failed', 'timed_out', 'skipped'));
CREATE OR REPLACE FUNCTION public.resolve_order_event_dispatch_ack_wait_seconds(
  p_retry_count INTEGER,
  p_payload JSONB DEFAULT '{}'::jsonb,
  p_default_seconds INTEGER DEFAULT 15
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_schedule_source JSONB := NULL;
  v_schedule INTEGER[] := ARRAY[10, 30, 300];
  v_schedule_length INTEGER := 3;
  v_retry_count INTEGER := GREATEST(COALESCE(p_retry_count, 0), 0);
  v_default_seconds INTEGER := GREATEST(COALESCE(p_default_seconds, 15), 0);
  v_previous_milestone INTEGER := 0;
  v_next_milestone INTEGER := NULL;
BEGIN
  IF jsonb_typeof(COALESCE(p_payload, '{}'::jsonb) -> 'dispatch_retry_schedule_seconds') = 'array' THEN
    v_schedule_source := p_payload -> 'dispatch_retry_schedule_seconds';
  ELSIF jsonb_typeof(COALESCE(p_payload, '{}'::jsonb) -> 'retry_schedule_seconds') = 'array' THEN
    v_schedule_source := p_payload -> 'retry_schedule_seconds';
  END IF;

  IF v_schedule_source IS NOT NULL THEN
    SELECT COALESCE(
      array_agg(GREATEST(value::INTEGER, 0) ORDER BY ordinality),
      ARRAY[10, 30, 300]
    )
    INTO v_schedule
    FROM jsonb_array_elements_text(v_schedule_source) WITH ORDINALITY AS t(value, ordinality)
    WHERE value ~ '^-?\d+$';
  END IF;

  v_schedule_length := COALESCE(array_length(v_schedule, 1), 0);
  IF v_schedule_length = 0 THEN
    RETURN v_default_seconds;
  END IF;

  IF v_retry_count > 0 THEN
    v_previous_milestone := COALESCE(
      v_schedule[LEAST(v_retry_count, v_schedule_length)],
      0
    );
  END IF;

  IF v_retry_count < v_schedule_length THEN
    v_next_milestone := v_schedule[v_retry_count + 1];
  END IF;

  IF v_next_milestone IS NULL THEN
    RETURN v_default_seconds;
  END IF;

  RETURN GREATEST(v_next_milestone - v_previous_milestone, 0);
END;
$$;
DROP FUNCTION IF EXISTS public.mark_order_event_dispatch_sent(UUID, TEXT, UUID, JSONB);
CREATE OR REPLACE FUNCTION public.mark_order_event_dispatch_sent(
  p_job_id UUID,
  p_worker_id TEXT DEFAULT NULL,
  p_notification_id UUID DEFAULT NULL,
  p_response_payload JSONB DEFAULT '{}'::jsonb,
  p_wait_for_ack BOOLEAN DEFAULT FALSE,
  p_ack_timeout_seconds INTEGER DEFAULT NULL
)
RETURNS public.order_event_dispatch_jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.order_event_dispatch_jobs%rowtype;
  v_ack_timeout_seconds INTEGER;
  v_wait_for_ack BOOLEAN := COALESCE(p_wait_for_ack, FALSE) AND p_notification_id IS NOT NULL;
BEGIN
  SELECT *
  INTO v_job
  FROM public.order_event_dispatch_jobs
  WHERE id = p_job_id
  FOR UPDATE;

  IF v_job.id IS NULL THEN
    RAISE EXCEPTION 'dispatch_job_not_found';
  END IF;

  v_ack_timeout_seconds := public.resolve_order_event_dispatch_ack_wait_seconds(
    p_retry_count := v_job.retry_count,
    p_payload := v_job.payload,
    p_default_seconds := COALESCE(
      p_ack_timeout_seconds,
      CASE
        WHEN jsonb_typeof(COALESCE(v_job.payload, '{}'::jsonb) -> 'dispatch_ack_timeout_seconds') IN ('number', 'string')
          AND COALESCE(v_job.payload ->> 'dispatch_ack_timeout_seconds', '') ~ '^-?\d+$'
          THEN GREATEST((v_job.payload ->> 'dispatch_ack_timeout_seconds')::INTEGER, 0)
        ELSE 15
      END
    )
  );

  UPDATE public.order_event_dispatch_jobs
  SET status = CASE WHEN v_wait_for_ack THEN 'waiting_ack' ELSE 'sent' END,
      notification_id = COALESCE(p_notification_id, notification_id),
      sent_at = NOW(),
      ack_required = v_wait_for_ack,
      ack_state = CASE WHEN v_wait_for_ack THEN 'pending' ELSE 'none' END,
      ack_timeout_at = CASE
        WHEN v_wait_for_ack THEN NOW() + make_interval(secs => v_ack_timeout_seconds)
        ELSE NULL
      END,
      acknowledged_at = NULL,
      ack_latency_ms = NULL,
      ack_payload = '{}'::jsonb,
      locked_at = NULL,
      locked_by = NULL,
      last_error = NULL,
      updated_at = NOW()
  WHERE id = p_job_id
  RETURNING * INTO v_job;

  UPDATE public.order_event_dispatch_attempts
  SET status = 'sent',
      response_payload = COALESCE(p_response_payload, '{}'::jsonb)
        || jsonb_build_object(
          'wait_for_ack', v_wait_for_ack,
          'ack_timeout_seconds', v_ack_timeout_seconds
        ),
      error_text = NULL
  WHERE id = (
    SELECT a.id
    FROM public.order_event_dispatch_attempts a
    WHERE a.job_id = p_job_id
      AND a.status = 'processing'
      AND (
        p_worker_id IS NULL
        OR COALESCE(a.worker_id, '') = COALESCE(p_worker_id, '')
      )
    ORDER BY a.created_at DESC
    LIMIT 1
  );

  RETURN v_job;
END;
$$;
CREATE OR REPLACE FUNCTION public.mark_order_event_dispatch_acknowledged(
  p_notification_id UUID,
  p_acknowledged_at TIMESTAMPTZ DEFAULT NOW(),
  p_ack_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
  v_acknowledged_at TIMESTAMPTZ := COALESCE(p_acknowledged_at, NOW());
BEGIN
  IF p_notification_id IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.order_event_dispatch_jobs j
  SET status = CASE
        WHEN j.ack_required THEN 'acked'
        ELSE j.status
      END,
      ack_state = CASE
        WHEN j.ack_required THEN 'acknowledged'
        ELSE j.ack_state
      END,
      acknowledged_at = COALESCE(j.acknowledged_at, v_acknowledged_at),
      ack_timeout_at = NULL,
      ack_latency_ms = CASE
        WHEN j.sent_at IS NULL THEN j.ack_latency_ms
        ELSE GREATEST(
          FLOOR(EXTRACT(EPOCH FROM (COALESCE(j.acknowledged_at, v_acknowledged_at) - j.sent_at)) * 1000)::INTEGER,
          0
        )
      END,
      ack_payload = COALESCE(j.ack_payload, '{}'::jsonb)
        || COALESCE(p_ack_payload, '{}'::jsonb)
        || jsonb_build_object(
          'acknowledged_at', v_acknowledged_at,
          'notification_id', p_notification_id
        ),
      updated_at = NOW()
  WHERE j.notification_id = p_notification_id
    AND j.status IN ('waiting_ack', 'sent', 'acked', 'failed');

  GET DIAGNOSTICS v_count = ROW_COUNT;

  UPDATE public.order_event_dispatch_attempts a
  SET status = 'acked',
      response_payload = COALESCE(a.response_payload, '{}'::jsonb)
        || COALESCE(p_ack_payload, '{}'::jsonb)
        || jsonb_build_object(
          'acknowledged_at', v_acknowledged_at,
          'notification_id', p_notification_id
        ),
      error_text = NULL
  WHERE a.id IN (
    SELECT a2.id
    FROM public.order_event_dispatch_attempts a2
    JOIN public.order_event_dispatch_jobs j
      ON j.id = a2.job_id
    WHERE j.notification_id = p_notification_id
      AND a2.status IN ('sent', 'timed_out')
    ORDER BY a2.created_at DESC
  );

  RETURN v_count;
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
  v_job public.order_event_dispatch_jobs%rowtype;
  v_notification public.push_notifications%rowtype;
  v_next_status TEXT;
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
    WHERE id = v_job.notification_id;

    IF v_notification.id IS NOT NULL
       AND (
         v_notification.app_delivered_at IS NOT NULL
         OR v_notification.opened_at IS NOT NULL
       ) THEN
      PERFORM public.mark_order_event_dispatch_acknowledged(
        p_notification_id := v_job.notification_id,
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

  IF v_job.status <> 'waiting_ack' OR v_job.ack_state <> 'pending' THEN
    RETURN v_job;
  END IF;

  v_next_status := CASE
    WHEN v_job.retry_count + 1 >= v_job.max_retries THEN 'dead_letter'
    ELSE 'failed'
  END;

  UPDATE public.order_event_dispatch_jobs
  SET status = v_next_status,
      retry_count = CASE
        WHEN v_next_status = 'dead_letter' THEN retry_count
        ELSE retry_count + 1
      END,
      next_attempt_at = CASE
        WHEN v_next_status = 'failed' THEN NOW()
        ELSE next_attempt_at
      END,
      ack_state = 'timed_out',
      ack_timeout_at = NULL,
      last_error = COALESCE(p_error_text, 'ack_timeout'),
      locked_at = NULL,
      locked_by = NULL,
      updated_at = NOW()
  WHERE id = p_job_id
  RETURNING * INTO v_job;

  UPDATE public.order_event_dispatch_attempts
  SET status = 'timed_out',
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
DROP VIEW IF EXISTS public.order_event_dispatch_health;
CREATE VIEW public.order_event_dispatch_health AS
SELECT
  COUNT(*) AS total_jobs,
  COUNT(*) FILTER (WHERE status = 'pending') AS pending_jobs,
  COUNT(*) FILTER (WHERE status = 'processing') AS processing_jobs,
  COUNT(*) FILTER (WHERE status = 'waiting_ack') AS waiting_ack_jobs,
  COUNT(*) FILTER (WHERE status = 'failed') AS failed_jobs,
  COUNT(*) FILTER (WHERE status = 'dead_letter') AS dead_letter_jobs,
  COUNT(*) FILTER (WHERE status = 'sent') AS sent_jobs,
  COUNT(*) FILTER (WHERE status = 'acked') AS acked_jobs,
  COUNT(*) FILTER (WHERE status = 'skipped') AS skipped_jobs,
  MIN(next_attempt_at) FILTER (WHERE status IN ('pending', 'failed')) AS next_due_at,
  MIN(ack_timeout_at) FILTER (WHERE status = 'waiting_ack') AS next_ack_timeout_at,
  MAX(updated_at) AS last_job_update_at
FROM public.order_event_dispatch_jobs;
DROP VIEW IF EXISTS public.order_event_dispatch_timeline;
CREATE VIEW public.order_event_dispatch_timeline AS
SELECT
  j.id AS job_id,
  j.event_id,
  j.order_id,
  j.event_topic,
  j.channel,
  j.target_role,
  j.target_user_id,
  j.handler,
  j.status,
  j.notification_key,
  j.retry_count,
  j.max_retries,
  j.next_attempt_at,
  j.last_attempt_at,
  j.locked_at,
  j.locked_by,
  j.last_error,
  j.notification_id,
  j.sent_at,
  j.ack_required,
  j.ack_state,
  j.ack_timeout_at,
  j.acknowledged_at,
  j.ack_latency_ms,
  j.created_at,
  a.id AS attempt_id,
  a.attempt_number,
  a.worker_id,
  a.status AS attempt_status,
  a.error_text,
  a.created_at AS attempt_created_at
FROM public.order_event_dispatch_jobs j
LEFT JOIN public.order_event_dispatch_attempts a
  ON a.job_id = j.id;
REVOKE ALL ON FUNCTION public.mark_order_event_dispatch_sent(UUID, TEXT, UUID, JSONB, BOOLEAN, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_order_event_dispatch_sent(UUID, TEXT, UUID, JSONB, BOOLEAN, INTEGER) TO service_role;
REVOKE ALL ON FUNCTION public.mark_order_event_dispatch_acknowledged(UUID, TIMESTAMPTZ, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_order_event_dispatch_acknowledged(UUID, TIMESTAMPTZ, JSONB) TO service_role;
REVOKE ALL ON FUNCTION public.timeout_waiting_order_event_dispatch_job(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.timeout_waiting_order_event_dispatch_job(UUID, TEXT) TO service_role;
REVOKE ALL ON FUNCTION public.reset_unacked_order_event_dispatch_jobs(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reset_unacked_order_event_dispatch_jobs(INTEGER) TO service_role;
COMMIT;
