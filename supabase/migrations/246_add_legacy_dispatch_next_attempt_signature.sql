BEGIN;
CREATE OR REPLACE FUNCTION public.resolve_order_event_dispatch_next_attempt_at(
  p_payload JSONB,
  p_retry_count INTEGER
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN public.resolve_order_event_dispatch_next_attempt_at(
    p_created_at := NOW(),
    p_retry_count := p_retry_count,
    p_payload := COALESCE(p_payload, '{}'::jsonb),
    p_retry_delay_seconds := NULL
  );
END;
$$;
COMMIT;
