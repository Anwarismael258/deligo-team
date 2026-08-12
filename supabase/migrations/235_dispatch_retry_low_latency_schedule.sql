CREATE OR REPLACE FUNCTION public.resolve_order_event_dispatch_retry_delay_seconds(
  p_retry_count INTEGER,
  p_payload JSONB DEFAULT '{}'::jsonb,
  p_retry_delay_seconds INTEGER DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_schedule_source JSONB := NULL;
  v_schedule INTEGER[] := ARRAY[10, 30, 300];
  v_schedule_length INTEGER := 3;
  v_index INTEGER := GREATEST(COALESCE(p_retry_count, 0), 0) + 1;
BEGIN
  IF p_retry_delay_seconds IS NOT NULL THEN
    RETURN GREATEST(p_retry_delay_seconds, 0);
  END IF;

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
    v_schedule := ARRAY[10, 30, 300];
    v_schedule_length := 3;
  END IF;

  RETURN COALESCE(
    v_schedule[LEAST(v_index, v_schedule_length)],
    300
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.resolve_order_event_dispatch_next_attempt_at(
  p_created_at TIMESTAMPTZ,
  p_retry_count INTEGER,
  p_payload JSONB DEFAULT '{}'::jsonb,
  p_retry_delay_seconds INTEGER DEFAULT NULL
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
AS $$
DECLARE
  v_delay_seconds INTEGER;
  v_created_at TIMESTAMPTZ := COALESCE(p_created_at, NOW());
BEGIN
  v_delay_seconds := public.resolve_order_event_dispatch_retry_delay_seconds(
    p_retry_count := p_retry_count,
    p_payload := p_payload,
    p_retry_delay_seconds := p_retry_delay_seconds
  );

  IF p_retry_delay_seconds IS NOT NULL THEN
    RETURN GREATEST(
      NOW(),
      NOW() + make_interval(secs => v_delay_seconds)
    );
  END IF;

  RETURN GREATEST(
    NOW(),
    v_created_at + make_interval(secs => v_delay_seconds)
  );
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
  SET status = CASE WHEN p_skip THEN 'skipped' ELSE 'failed' END,
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
CREATE OR REPLACE FUNCTION public.reset_stale_order_event_dispatch_jobs(
  p_stale_after_minutes INTEGER DEFAULT 10
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  UPDATE public.order_event_dispatch_jobs
  SET status = CASE
        WHEN retry_count + 1 >= max_retries THEN 'dead_letter'
        ELSE 'failed'
      END,
      retry_count = CASE
        WHEN retry_count + 1 >= max_retries THEN retry_count
        ELSE retry_count + 1
      END,
      next_attempt_at = CASE
        WHEN retry_count + 1 >= max_retries THEN next_attempt_at
        ELSE public.resolve_order_event_dispatch_next_attempt_at(
          p_created_at := created_at,
          p_retry_count := retry_count,
          p_payload := payload,
          p_retry_delay_seconds := NULL
        )
      END,
      locked_at = NULL,
      locked_by = NULL,
      last_error = COALESCE(last_error, 'stale_processing_lock_reset'),
      updated_at = NOW()
  WHERE status = 'processing'
    AND locked_at <= NOW() - make_interval(mins => LEAST(GREATEST(COALESCE(p_stale_after_minutes, 10), 1), 120));

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
