BEGIN;
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
COMMIT;
