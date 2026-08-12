BEGIN;
ALTER TABLE IF EXISTS public.order_event_dispatch_attempts
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
ALTER TABLE IF EXISTS public.order_event_dispatch_attempts
  DROP CONSTRAINT IF EXISTS order_event_dispatch_attempts_status_check;
ALTER TABLE IF EXISTS public.order_event_dispatch_attempts
  ADD CONSTRAINT order_event_dispatch_attempts_status_check
  CHECK (status IN ('processing', 'sent', 'acked', 'failed', 'timed_out', 'skipped', 'dead_letter'));
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
      completed_at = CASE
        WHEN v_wait_for_ack THEN NULL
        ELSE NOW()
      END,
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
CREATE OR REPLACE FUNCTION public.mark_order_event_dispatch_failed(
  p_job_id UUID,
  p_worker_id TEXT DEFAULT NULL,
  p_error_text TEXT DEFAULT NULL,
  p_response_payload JSONB DEFAULT '{}'::jsonb,
  p_retry_delay_seconds INTEGER DEFAULT NULL,
  p_skip BOOLEAN DEFAULT FALSE
)
RETURNS public.order_event_dispatch_jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.order_event_dispatch_jobs%rowtype;
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

  v_next_status := CASE
    WHEN p_skip THEN 'skipped'
    WHEN v_job.retry_count + 1 >= v_job.max_retries THEN 'dead_letter'
    ELSE 'failed'
  END;

  UPDATE public.order_event_dispatch_jobs
  SET status = v_next_status,
      retry_count = CASE
        WHEN p_skip THEN retry_count
        ELSE retry_count + 1
      END,
      next_attempt_at = CASE
        WHEN v_next_status = 'failed' THEN public.resolve_order_event_dispatch_next_attempt_at(
          p_created_at := v_job.created_at,
          p_retry_count := v_job.retry_count,
          p_payload := v_job.payload,
          p_retry_delay_seconds := p_retry_delay_seconds
        )
        ELSE next_attempt_at
      END,
      locked_at = NULL,
      locked_by = NULL,
      last_error = COALESCE(p_error_text, last_error, 'dispatch_failed'),
      updated_at = NOW()
  WHERE id = p_job_id
  RETURNING * INTO v_job;

  UPDATE public.order_event_dispatch_attempts
  SET status = CASE
        WHEN p_skip THEN 'skipped'
        WHEN v_next_status = 'dead_letter' THEN 'dead_letter'
        ELSE 'failed'
      END,
      completed_at = NOW(),
      response_payload = COALESCE(p_response_payload, '{}'::jsonb),
      error_text = COALESCE(p_error_text, error_text, 'dispatch_failed')
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
    AND j.status IN ('waiting_ack', 'sent', 'acked', 'failed', 'dead_letter');

  GET DIAGNOSTICS v_count = ROW_COUNT;

  UPDATE public.order_event_dispatch_attempts a
  SET status = 'acked',
      completed_at = v_acknowledged_at,
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
      AND a2.status IN ('sent', 'timed_out', 'failed', 'dead_letter')
    ORDER BY a2.created_at DESC
  );

  RETURN v_count;
END;
$$;
UPDATE public.order_event_dispatch_attempts a
SET status = 'dead_letter'
FROM public.order_event_dispatch_jobs j
WHERE j.id = a.job_id
  AND j.status = 'dead_letter'
  AND a.status = 'failed'
  AND a.id = (
    SELECT a2.id
    FROM public.order_event_dispatch_attempts a2
    WHERE a2.job_id = a.job_id
    ORDER BY a2.attempt_number DESC, a2.created_at DESC
    LIMIT 1
  );
WITH attempt_context AS (
  SELECT
    a.id,
    a.status,
    a.created_at,
    j.status AS job_status,
    j.ack_state,
    j.sent_at,
    j.acknowledged_at,
    j.updated_at AS job_updated_at,
    (
      SELECT a2.created_at
      FROM public.order_event_dispatch_attempts a2
      WHERE a2.job_id = a.job_id
        AND (
          a2.attempt_number > a.attempt_number
          OR (a2.attempt_number = a.attempt_number AND a2.created_at > a.created_at)
        )
      ORDER BY a2.attempt_number, a2.created_at
      LIMIT 1
    ) AS next_attempt_created_at
  FROM public.order_event_dispatch_attempts a
  JOIN public.order_event_dispatch_jobs j
    ON j.id = a.job_id
  WHERE a.completed_at IS NULL
    AND a.status IN ('sent', 'failed', 'skipped', 'dead_letter', 'acked', 'timed_out')
)
UPDATE public.order_event_dispatch_attempts a
SET completed_at = COALESCE(
  CASE
    WHEN c.status = 'acked' THEN c.acknowledged_at
    WHEN c.status = 'timed_out' THEN COALESCE(c.next_attempt_created_at, c.job_updated_at, c.sent_at)
    WHEN c.status = 'sent'
      AND NOT (c.job_status = 'waiting_ack' AND COALESCE(c.ack_state, 'pending') = 'pending')
      THEN COALESCE(c.sent_at, c.job_updated_at)
    WHEN c.status IN ('failed', 'skipped', 'dead_letter')
      THEN COALESCE(c.next_attempt_created_at, c.job_updated_at)
    ELSE NULL
  END,
  c.next_attempt_created_at,
  c.created_at,
  NOW()
)
FROM attempt_context c
WHERE a.id = c.id
  AND NOT (
    c.status = 'sent'
    AND c.job_status = 'waiting_ack'
    AND COALESCE(c.ack_state, 'pending') = 'pending'
  );
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
  a.created_at AS attempt_created_at,
  a.completed_at AS attempt_completed_at
FROM public.order_event_dispatch_jobs j
LEFT JOIN public.order_event_dispatch_attempts a
  ON a.job_id = j.id;
COMMIT;
