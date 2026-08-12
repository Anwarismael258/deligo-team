BEGIN;
ALTER TABLE IF EXISTS public.profiles
  ADD COLUMN IF NOT EXISTS trust_score INTEGER NOT NULL DEFAULT 50,
  ADD COLUMN IF NOT EXISTS risk_level TEXT NOT NULL DEFAULT 'medium',
  ADD COLUMN IF NOT EXISTS trust_last_evaluated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS trust_flags JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE IF EXISTS public.profiles
  DROP CONSTRAINT IF EXISTS profiles_trust_score_range;
ALTER TABLE IF EXISTS public.profiles
  ADD CONSTRAINT profiles_trust_score_range
  CHECK (trust_score BETWEEN 0 AND 100);
CREATE TABLE IF NOT EXISTS public.user_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.user_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  device_fingerprint TEXT NOT NULL,
  device_model TEXT,
  os_name TEXT,
  app_version TEXT,
  ip_address INET,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, device_fingerprint)
);
CREATE TABLE IF NOT EXISTS public.reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reported_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reporter_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_user_events_user_created_at
  ON public.user_events(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_events_type_created_at
  ON public.user_events(event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_devices_fingerprint
  ON public.user_devices(device_fingerprint);
CREATE INDEX IF NOT EXISTS idx_reports_reported_user
  ON public.reports(reported_user_id, created_at DESC);
ALTER TABLE public.user_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_events_select_own ON public.user_events;
CREATE POLICY user_events_select_own
ON public.user_events
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS user_events_insert_self ON public.user_events;
CREATE POLICY user_events_insert_self
ON public.user_events
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS user_events_service_all ON public.user_events;
CREATE POLICY user_events_service_all
ON public.user_events
FOR ALL TO service_role
USING (true)
WITH CHECK (true);
DROP POLICY IF EXISTS user_devices_select_own ON public.user_devices;
CREATE POLICY user_devices_select_own
ON public.user_devices
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS user_devices_insert_self ON public.user_devices;
CREATE POLICY user_devices_insert_self
ON public.user_devices
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS user_devices_update_self ON public.user_devices;
CREATE POLICY user_devices_update_self
ON public.user_devices
FOR UPDATE TO authenticated
USING (user_id = auth.uid() OR public.is_admin())
WITH CHECK (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS user_devices_service_all ON public.user_devices;
CREATE POLICY user_devices_service_all
ON public.user_devices
FOR ALL TO service_role
USING (true)
WITH CHECK (true);
DROP POLICY IF EXISTS reports_select_related ON public.reports;
CREATE POLICY reports_select_related
ON public.reports
FOR SELECT TO authenticated
USING (reported_user_id = auth.uid() OR reporter_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS reports_insert_self ON public.reports;
CREATE POLICY reports_insert_self
ON public.reports
FOR INSERT TO authenticated
WITH CHECK (reporter_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS reports_service_all ON public.reports;
CREATE POLICY reports_service_all
ON public.reports
FOR ALL TO service_role
USING (true)
WITH CHECK (true);
CREATE OR REPLACE FUNCTION public.update_trust_score(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_profile public.profiles%ROWTYPE;
  v_score INTEGER := 100;
  v_device_accounts INTEGER := 0;
  v_cancel_count INTEGER := 0;
  v_report_count INTEGER := 0;
  v_financial_fraud INTEGER := 0;
  v_flag_count INTEGER := 0;
  v_reliability NUMERIC := 100;
  v_risk_level TEXT := 'low';
  v_flags JSONB := '[]'::jsonb;
BEGIN
  SELECT *
  INTO v_profile
  FROM public.profiles
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'profile_not_found');
  END IF;

  SELECT COUNT(DISTINCT ud.user_id)
  INTO v_device_accounts
  FROM public.user_devices ud
  WHERE ud.device_fingerprint IN (
    SELECT device_fingerprint
    FROM public.user_devices
    WHERE user_id = p_user_id
  );

  IF v_device_accounts > 3 THEN
    v_score := v_score - 40;
    v_flags := v_flags || jsonb_build_array('same_device_multiple_accounts');
  END IF;

  SELECT COUNT(*)
  INTO v_cancel_count
  FROM public.user_events
  WHERE user_id = p_user_id
    AND event_type = 'order_cancel'
    AND created_at >= now() - interval '30 days';

  IF v_cancel_count > 5 THEN
    v_score := v_score - 20;
    v_flags := v_flags || jsonb_build_array('excessive_order_cancellations');
  END IF;

  SELECT COUNT(*)
  INTO v_report_count
  FROM public.reports
  WHERE reported_user_id = p_user_id
    AND created_at >= now() - interval '60 days';

  IF v_report_count >= 3 THEN
    v_score := v_score - 15;
    v_flags := v_flags || jsonb_build_array('community_reports');
  END IF;

  SELECT COUNT(*)
  INTO v_financial_fraud
  FROM public.user_fraud_events
  WHERE user_id = p_user_id
    AND created_at >= now() - interval '60 days';

  IF v_financial_fraud > 0 THEN
    v_score := GREATEST(0, v_score - LEAST(v_financial_fraud * 5, 30));
    v_flags := v_flags || jsonb_build_array('financial_risk');
  END IF;

  IF v_profile.role = 'courier' THEN
    SELECT COALESCE(reliability_score, 100)
    INTO v_reliability
    FROM public.couriers
    WHERE id = p_user_id;

    IF v_reliability < 70 THEN
      v_score := v_score - 15;
      v_flags := v_flags || jsonb_build_array('low_courier_reliability');
    END IF;
  END IF;

  IF COALESCE(v_profile.verification_score, 0) < 50 THEN
    v_score := v_score - 20;
    v_flags := v_flags || jsonb_build_array('low_verification_score');
  END IF;

  IF COALESCE(v_profile.is_blocked, FALSE) THEN
    v_score := LEAST(v_score, 20);
    v_flags := v_flags || jsonb_build_array('already_blocked');
  END IF;

  v_score := LEAST(GREATEST(v_score, 0), 100);
  v_risk_level := CASE
    WHEN v_score >= 80 THEN 'low'
    WHEN v_score >= 50 THEN 'medium'
    ELSE 'high'
  END;

  SELECT jsonb_array_length(v_flags)
  INTO v_flag_count;

  UPDATE public.profiles
  SET
    trust_score = v_score,
    risk_level = v_risk_level,
    trust_flags = COALESCE(v_flags, '[]'::jsonb),
    trust_last_evaluated_at = now(),
    is_suspicious = CASE WHEN v_risk_level <> 'low' THEN TRUE ELSE COALESCE(is_suspicious, FALSE) END,
    is_blocked = CASE
      WHEN v_risk_level = 'high' AND v_score < 40 THEN TRUE
      ELSE COALESCE(is_blocked, FALSE)
    END,
    block_reason = CASE
      WHEN v_risk_level = 'high' AND v_score < 40 THEN
        COALESCE(block_reason, 'Conta bloqueada automaticamente por alto risco.')
      ELSE block_reason
    END,
    updated_at = now()
  WHERE id = p_user_id;

  IF v_risk_level = 'high' AND v_score < 40 THEN
    PERFORM public.create_app_notification(
      p_user_id,
      'SYSTEM_ALERT',
      'Conta em revisao de seguranca',
      'Detectamos risco elevado nesta conta. O acesso pode ficar limitado ate revisao.',
      'OPEN_SUPPORT',
      p_user_id::text,
      'HIGH',
      'trust_safety',
      jsonb_build_object('trust_score', v_score, 'risk_level', v_risk_level, 'flags', v_flags)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'trust_score', v_score,
    'risk_level', v_risk_level,
    'flag_count', v_flag_count,
    'flags', v_flags
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.register_user_event(
  p_user_id UUID,
  p_event_type TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.user_events (user_id, event_type, metadata)
  VALUES (p_user_id, p_event_type, COALESCE(p_metadata, '{}'::jsonb))
  RETURNING id INTO v_id;

  IF p_event_type IN (
    'same_device_multiple_accounts',
    'order_cancel',
    'payment_attempt',
    'location_update',
    'driver_idle_suspected',
    'restaurant_timeout_pattern',
    'report_received'
  ) THEN
    PERFORM public.update_trust_score(p_user_id);
  END IF;

  RETURN v_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.register_user_device(
  p_user_id UUID,
  p_device_fingerprint TEXT,
  p_device_model TEXT DEFAULT NULL,
  p_os_name TEXT DEFAULT NULL,
  p_app_version TEXT DEFAULT NULL,
  p_ip_address INET DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_account_count INTEGER := 0;
BEGIN
  INSERT INTO public.user_devices (
    user_id,
    device_fingerprint,
    device_model,
    os_name,
    app_version,
    ip_address,
    created_at,
    updated_at
  )
  VALUES (
    p_user_id,
    p_device_fingerprint,
    p_device_model,
    p_os_name,
    p_app_version,
    p_ip_address,
    now(),
    now()
  )
  ON CONFLICT (user_id, device_fingerprint) DO UPDATE
    SET device_model = COALESCE(EXCLUDED.device_model, public.user_devices.device_model),
        os_name = COALESCE(EXCLUDED.os_name, public.user_devices.os_name),
        app_version = COALESCE(EXCLUDED.app_version, public.user_devices.app_version),
        ip_address = COALESCE(EXCLUDED.ip_address, public.user_devices.ip_address),
        updated_at = now();

  SELECT COUNT(DISTINCT user_id)
  INTO v_account_count
  FROM public.user_devices
  WHERE device_fingerprint = p_device_fingerprint;

  IF v_account_count > 3 THEN
    PERFORM public.register_user_event(
      p_user_id,
      'same_device_multiple_accounts',
      jsonb_build_object(
        'device_fingerprint', p_device_fingerprint,
        'account_count', v_account_count
      )
    );
  ELSE
    PERFORM public.register_user_event(
      p_user_id,
      'device_registered',
      jsonb_build_object('device_fingerprint', p_device_fingerprint)
    );
  END IF;

  RETURN public.update_trust_score(p_user_id);
END;
$$;
CREATE OR REPLACE FUNCTION public.submit_user_report(
  p_reported_user_id UUID,
  p_reason TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_report_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  INSERT INTO public.reports (
    reported_user_id,
    reporter_id,
    reason,
    metadata
  )
  VALUES (
    p_reported_user_id,
    auth.uid(),
    p_reason,
    COALESCE(p_metadata, '{}'::jsonb)
  )
  RETURNING id INTO v_report_id;

  PERFORM public.register_user_event(
    p_reported_user_id,
    'report_received',
    jsonb_build_object('reason', p_reason, 'report_id', v_report_id)
  );

  RETURN v_report_id;
END;
$$;
CREATE OR REPLACE VIEW public.admin_trust_overview AS
SELECT
  p.id,
  p.full_name,
  p.role,
  p.kyc_status,
  p.trust_score,
  p.risk_level,
  p.is_blocked,
  p.block_reason,
  p.trust_last_evaluated_at,
  p.verification_score,
  p.fraud_score,
  c.reliability_score
FROM public.profiles p
LEFT JOIN public.couriers c ON c.id = p.id;
COMMIT;
