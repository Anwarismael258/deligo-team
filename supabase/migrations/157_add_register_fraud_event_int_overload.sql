CREATE OR REPLACE FUNCTION public.register_user_fraud_event(
  p_user_id UUID,
  p_event_type TEXT,
  p_points INTEGER DEFAULT 0,
  p_severity INTEGER DEFAULT 0,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_severity TEXT;
BEGIN
  v_severity := CASE
    WHEN p_severity >= 15 THEN 'high'
    WHEN p_severity >= 5 THEN 'medium'
    ELSE 'low'
  END;

  PERFORM public.register_user_fraud_event(
    p_user_id,
    p_event_type,
    p_points,
    v_severity,
    p_metadata
  );
END;
$$;
