CREATE TABLE IF NOT EXISTS public.registration_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT,
  phone TEXT,
  device_fingerprint TEXT NOT NULL,
  role TEXT,
  result TEXT NOT NULL DEFAULT 'attempt',
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_registration_attempts_device_created
  ON public.registration_attempts(device_fingerprint, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_registration_attempts_email_created
  ON public.registration_attempts(email, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_registration_attempts_phone_created
  ON public.registration_attempts(phone, created_at DESC);
ALTER TABLE public.registration_attempts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS registration_attempts_service_all ON public.registration_attempts;
CREATE POLICY registration_attempts_service_all
ON public.registration_attempts
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);
DROP POLICY IF EXISTS registration_attempts_admin_select ON public.registration_attempts;
CREATE POLICY registration_attempts_admin_select
ON public.registration_attempts
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role = 'admin'
  )
);
CREATE OR REPLACE FUNCTION public.check_registration_guard(
  p_email TEXT,
  p_phone TEXT,
  p_device_fingerprint TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_email TEXT := lower(trim(COALESCE(p_email, '')));
  v_phone TEXT := trim(COALESCE(p_phone, ''));
  v_email_exists BOOLEAN := FALSE;
  v_phone_exists BOOLEAN := FALSE;
  v_attempt_count INTEGER := 0;
  v_device_blocked BOOLEAN := FALSE;
BEGIN
  IF v_email <> '' THEN
    SELECT EXISTS (
      SELECT 1
      FROM auth.users
      WHERE lower(email) = v_email
    )
    INTO v_email_exists;
  END IF;

  IF v_phone <> '' THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.profiles
      WHERE phone = v_phone
    )
    INTO v_phone_exists;
  END IF;

  SELECT COUNT(*)
  INTO v_attempt_count
  FROM public.registration_attempts
  WHERE device_fingerprint = COALESCE(p_device_fingerprint, '')
    AND created_at >= now() - interval '12 hours'
    AND result IN ('attempt', 'failed', 'blocked');

  v_device_blocked := v_attempt_count >= 5;

  RETURN jsonb_build_object(
    'allowed', NOT v_email_exists AND NOT v_phone_exists AND NOT v_device_blocked,
    'email_exists', v_email_exists,
    'phone_exists', v_phone_exists,
    'device_blocked', v_device_blocked,
    'attempt_count', v_attempt_count
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.check_registration_guard(TEXT, TEXT, TEXT) TO anon, authenticated, service_role;
CREATE OR REPLACE FUNCTION public.record_registration_attempt(
  p_email TEXT,
  p_phone TEXT,
  p_device_fingerprint TEXT,
  p_result TEXT DEFAULT 'attempt',
  p_reason TEXT DEFAULT NULL,
  p_role TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  INSERT INTO public.registration_attempts (
    email,
    phone,
    device_fingerprint,
    role,
    result,
    reason
  )
  VALUES (
    NULLIF(lower(trim(COALESCE(p_email, ''))), ''),
    NULLIF(trim(COALESCE(p_phone, '')), ''),
    COALESCE(NULLIF(trim(COALESCE(p_device_fingerprint, '')), ''), 'unknown-device'),
    NULLIF(trim(COALESCE(p_role, '')), ''),
    COALESCE(NULLIF(trim(COALESCE(p_result, '')), ''), 'attempt'),
    NULLIF(trim(COALESCE(p_reason, '')), '')
  );

  SELECT COUNT(*)
  INTO v_count
  FROM public.registration_attempts
  WHERE device_fingerprint = COALESCE(NULLIF(trim(COALESCE(p_device_fingerprint, '')), ''), 'unknown-device')
    AND created_at >= now() - interval '12 hours'
    AND result IN ('attempt', 'failed', 'blocked');

  RETURN jsonb_build_object(
    'success', true,
    'attempt_count', v_count,
    'device_blocked', v_count >= 5
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.record_registration_attempt(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;
