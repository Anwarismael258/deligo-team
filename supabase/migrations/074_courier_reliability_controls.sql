BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
ALTER TABLE IF EXISTS public.profiles
  ADD COLUMN IF NOT EXISTS is_suspicious BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS block_reason TEXT,
  ADD COLUMN IF NOT EXISTS last_fraud_event_at TIMESTAMPTZ;
ALTER TABLE IF EXISTS public.couriers
  ADD COLUMN IF NOT EXISTS failed_deliveries INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS late_deliveries INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS theft_reports INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS offline_abandonments INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS incident_points INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reliability_score NUMERIC DEFAULT 100,
  ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS suspension_reason TEXT,
  ADD COLUMN IF NOT EXISTS suspension_until TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_incident_at TIMESTAMPTZ;
CREATE TABLE IF NOT EXISTS public.courier_incident_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id UUID NOT NULL REFERENCES public.couriers(id) ON DELETE CASCADE,
  order_id UUID NULL REFERENCES public.orders(id) ON DELETE SET NULL,
  incident_type TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'medium',
  points INTEGER NOT NULL DEFAULT 0,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_courier_incident_events_courier_created
  ON public.courier_incident_events(courier_id, created_at DESC);
ALTER TABLE public.courier_incident_events ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'courier_incident_events_select_own'
      AND polrelid = 'public.courier_incident_events'::regclass
  ) THEN
    CREATE POLICY courier_incident_events_select_own
      ON public.courier_incident_events
      FOR SELECT
      TO authenticated
      USING (courier_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'courier_incident_events_service_all'
      AND polrelid = 'public.courier_incident_events'::regclass
  ) THEN
    CREATE POLICY courier_incident_events_service_all
      ON public.courier_incident_events
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
CREATE OR REPLACE FUNCTION public.register_courier_incident(
  p_courier_id UUID,
  p_incident_type TEXT,
  p_order_id UUID DEFAULT NULL,
  p_points INTEGER DEFAULT NULL,
  p_severity TEXT DEFAULT 'medium',
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_points INTEGER := COALESCE(
    p_points,
    CASE p_incident_type
      WHEN 'delivery_not_completed' THEN 30
      WHEN 'late_delivery' THEN 12
      WHEN 'courier_cancelled_assignment' THEN 15
      WHEN 'offline_after_accept' THEN 25
      WHEN 'theft_report' THEN 80
      WHEN 'fake_delivery_confirmation' THEN 45
      ELSE 10
    END
  );
  v_existing_id UUID;
  v_courier RECORD;
  v_new_points INTEGER;
  v_new_score NUMERIC;
  v_suspend BOOLEAN := FALSE;
  v_suspend_reason TEXT;
  v_suspend_until TIMESTAMPTZ;
  v_failed_increment INTEGER := CASE WHEN p_incident_type IN ('delivery_not_completed', 'fake_delivery_confirmation') THEN 1 ELSE 0 END;
  v_late_increment INTEGER := CASE WHEN p_incident_type = 'late_delivery' THEN 1 ELSE 0 END;
  v_theft_increment INTEGER := CASE WHEN p_incident_type = 'theft_report' THEN 1 ELSE 0 END;
  v_offline_increment INTEGER := CASE WHEN p_incident_type = 'offline_after_accept' THEN 1 ELSE 0 END;
BEGIN
  IF p_courier_id IS NULL THEN
    RAISE EXCEPTION 'courier_id_required';
  END IF;

  IF p_order_id IS NOT NULL THEN
    SELECT id
    INTO v_existing_id
    FROM public.courier_incident_events
    WHERE courier_id = p_courier_id
      AND order_id = p_order_id
      AND incident_type = p_incident_type
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', true,
        'duplicate', true,
        'incident_id', v_existing_id
      );
    END IF;
  END IF;

  INSERT INTO public.courier_incident_events (
    courier_id,
    order_id,
    incident_type,
    severity,
    points,
    metadata
  ) VALUES (
    p_courier_id,
    p_order_id,
    p_incident_type,
    COALESCE(NULLIF(TRIM(p_severity), ''), 'medium'),
    v_points,
    COALESCE(p_metadata, '{}'::jsonb)
  )
  RETURNING id INTO v_existing_id;

  UPDATE public.couriers
  SET failed_deliveries = COALESCE(failed_deliveries, 0) + v_failed_increment,
      late_deliveries = COALESCE(late_deliveries, 0) + v_late_increment,
      theft_reports = COALESCE(theft_reports, 0) + v_theft_increment,
      offline_abandonments = COALESCE(offline_abandonments, 0) + v_offline_increment,
      incident_points = COALESCE(incident_points, 0) + v_points,
      last_incident_at = NOW(),
      updated_at = NOW()
  WHERE id = p_courier_id;

  SELECT *
  INTO v_courier
  FROM public.couriers
  WHERE id = p_courier_id
  LIMIT 1;

  v_new_points := COALESCE(v_courier.incident_points, 0);
  v_new_score := GREATEST(0, 100 - v_new_points);

  IF COALESCE(v_courier.theft_reports, 0) >= 1 THEN
    v_suspend := TRUE;
    v_suspend_reason := 'Bloqueado por suspeita grave de desvio de pedido.';
    v_suspend_until := NULL;
  ELSIF COALESCE(v_courier.failed_deliveries, 0) >= 3 THEN
    v_suspend := TRUE;
    v_suspend_reason := 'Bloqueado automaticamente por falhas repetidas de entrega.';
    v_suspend_until := NOW() + INTERVAL '30 days';
  ELSIF COALESCE(v_courier.offline_abandonments, 0) >= 2 THEN
    v_suspend := TRUE;
    v_suspend_reason := 'Bloqueado por ficar offline apos aceitar entregas.';
    v_suspend_until := NOW() + INTERVAL '14 days';
  ELSIF COALESCE(v_courier.late_deliveries, 0) >= 5 THEN
    v_suspend := TRUE;
    v_suspend_reason := 'Bloqueado por atrasos recorrentes acima do permitido.';
    v_suspend_until := NOW() + INTERVAL '7 days';
  ELSIF v_new_points >= 80 THEN
    v_suspend := TRUE;
    v_suspend_reason := 'Bloqueado automaticamente por risco operacional elevado.';
    v_suspend_until := NOW() + INTERVAL '30 days';
  END IF;

  UPDATE public.couriers
  SET reliability_score = v_new_score,
      is_suspended = v_suspend,
      suspension_reason = CASE WHEN v_suspend THEN v_suspend_reason ELSE NULL END,
      suspension_until = CASE WHEN v_suspend THEN v_suspend_until ELSE NULL END,
      updated_at = NOW()
  WHERE id = p_courier_id;

  UPDATE public.profiles
  SET is_suspicious = CASE WHEN v_new_points >= 40 THEN TRUE ELSE COALESCE(is_suspicious, FALSE) END,
      is_blocked = CASE WHEN v_suspend THEN TRUE ELSE COALESCE(is_blocked, FALSE) END,
      block_reason = CASE WHEN v_suspend THEN v_suspend_reason ELSE block_reason END,
      last_fraud_event_at = NOW(),
      updated_at = NOW()
  WHERE id = p_courier_id;

  RETURN jsonb_build_object(
    'success', true,
    'incident_id', v_existing_id,
    'courier_id', p_courier_id,
    'incident_type', p_incident_type,
    'points', v_points,
    'reliability_score', v_new_score,
    'is_suspended', v_suspend,
    'suspension_reason', v_suspend_reason
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.enforce_courier_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile RECORD;
  v_courier RECORD;
BEGIN
  IF NEW.courier_id IS NULL OR (TG_OP = 'UPDATE' AND NEW.courier_id IS NOT DISTINCT FROM OLD.courier_id) THEN
    RETURN NEW;
  END IF;

  SELECT id, role, kyc_status, is_blocked
  INTO v_profile
  FROM public.profiles
  WHERE id = NEW.courier_id
  LIMIT 1;

  IF v_profile.id IS NULL OR v_profile.role <> 'courier' THEN
    RAISE EXCEPTION 'courier_profile_invalid';
  END IF;

  IF COALESCE(v_profile.kyc_status, 'pending') <> 'approved' THEN
    RAISE EXCEPTION 'courier_kyc_not_approved';
  END IF;

  IF COALESCE(v_profile.is_blocked, FALSE) THEN
    RAISE EXCEPTION 'courier_blocked';
  END IF;

  SELECT id, is_suspended, suspension_until
  INTO v_courier
  FROM public.couriers
  WHERE id = NEW.courier_id
  LIMIT 1;

  IF v_courier.id IS NULL THEN
    RAISE EXCEPTION 'courier_not_found';
  END IF;

  IF COALESCE(v_courier.is_suspended, FALSE)
     AND (v_courier.suspension_until IS NULL OR v_courier.suspension_until > NOW()) THEN
    RAISE EXCEPTION 'courier_suspended';
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_courier_assignment ON public.orders;
CREATE TRIGGER trg_enforce_courier_assignment
BEFORE INSERT OR UPDATE OF courier_id
ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.enforce_courier_assignment();
CREATE OR REPLACE FUNCTION public.track_courier_online_state()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_active_order_id UUID;
BEGIN
  IF COALESCE(OLD.is_online, FALSE) = TRUE
     AND COALESCE(NEW.is_online, FALSE) = FALSE THEN
    SELECT id
    INTO v_active_order_id
    FROM public.orders
    WHERE courier_id = NEW.id
      AND status IN ('courier_assigned', 'in_transit', 'arrived')
    ORDER BY updated_at DESC NULLS LAST
    LIMIT 1;

    IF v_active_order_id IS NOT NULL THEN
      PERFORM public.register_courier_incident(
        NEW.id,
        'offline_after_accept',
        v_active_order_id,
        25,
        'high',
        jsonb_build_object(
          'source', 'courier_online_trigger',
          'previous_online', OLD.is_online,
          'new_online', NEW.is_online
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_track_courier_online_state ON public.couriers;
CREATE TRIGGER trg_track_courier_online_state
AFTER UPDATE OF is_online
ON public.couriers
FOR EACH ROW
EXECUTE FUNCTION public.track_courier_online_state();
CREATE OR REPLACE FUNCTION public.track_courier_order_transitions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;

  IF OLD.courier_id IS NOT NULL
     AND NEW.courier_id IS NULL
     AND COALESCE(OLD.status, '') IN ('courier_assigned', 'in_transit', 'arrived')
     AND COALESCE(NEW.status, '') IN ('accepted', 'ready', 'cancelled') THEN
    PERFORM public.register_courier_incident(
      OLD.courier_id,
      'courier_cancelled_assignment',
      NEW.id,
      15,
      'medium',
      jsonb_build_object(
        'old_status', OLD.status,
        'new_status', NEW.status,
        'source', 'order_transition_trigger'
      )
    );
  END IF;

  IF NEW.courier_id IS NOT NULL
     AND COALESCE(OLD.status, '') IS DISTINCT FROM COALESCE(NEW.status, '')
     AND NEW.status = 'delivered' THEN
    UPDATE public.couriers
    SET total_deliveries = COALESCE(total_deliveries, 0) + 1,
        updated_at = NOW()
    WHERE id = NEW.courier_id;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_track_courier_order_transitions ON public.orders;
CREATE TRIGGER trg_track_courier_order_transitions
AFTER UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.track_courier_order_transitions();
CREATE OR REPLACE VIEW public.admin_courier_risk_overview AS
SELECT
  c.id AS courier_id,
  COALESCE(c.full_name, p.full_name) AS full_name,
  COALESCE(c.phone, p.phone) AS phone,
  p.kyc_status,
  COALESCE(c.rating, 0) AS rating,
  COALESCE(c.total_deliveries, 0) AS total_deliveries,
  COALESCE(c.acceptance_rate, 0) AS acceptance_rate,
  COALESCE(c.cancellation_rate, 0) AS cancellation_rate,
  COALESCE(c.failed_deliveries, 0) AS failed_deliveries,
  COALESCE(c.late_deliveries, 0) AS late_deliveries,
  COALESCE(c.theft_reports, 0) AS theft_reports,
  COALESCE(c.offline_abandonments, 0) AS offline_abandonments,
  COALESCE(c.incident_points, 0) AS incident_points,
  COALESCE(c.reliability_score, 100) AS reliability_score,
  COALESCE(c.is_suspended, FALSE) AS is_suspended,
  c.suspension_reason,
  c.suspension_until,
  COALESCE(p.is_suspicious, FALSE) AS is_suspicious,
  COALESCE(p.is_blocked, FALSE) AS is_blocked,
  p.block_reason,
  COALESCE(active_orders.active_order_count, 0) AS active_order_count,
  COALESCE(active_orders.over_sla_assignments, 0) AS over_sla_assignments,
  COALESCE(active_orders.over_sla_transit, 0) AS over_sla_transit,
  COALESCE(incidents.incidents_last_7d, 0) AS incidents_last_7d,
  COALESCE(incidents.high_severity_last_30d, 0) AS high_severity_last_30d,
  c.last_incident_at,
  c.updated_at
FROM public.couriers c
LEFT JOIN public.profiles p ON p.id = c.id
LEFT JOIN (
  SELECT
    courier_id,
    COUNT(*) FILTER (WHERE status IN ('courier_assigned', 'in_transit', 'arrived')) AS active_order_count,
    COUNT(*) FILTER (WHERE status = 'courier_assigned' AND updated_at < NOW() - INTERVAL '20 minutes') AS over_sla_assignments,
    COUNT(*) FILTER (WHERE status IN ('in_transit', 'arrived') AND updated_at < NOW() - INTERVAL '60 minutes') AS over_sla_transit
  FROM public.orders
  WHERE courier_id IS NOT NULL
  GROUP BY courier_id
) active_orders ON active_orders.courier_id = c.id
LEFT JOIN (
  SELECT
    courier_id,
    COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days') AS incidents_last_7d,
    COUNT(*) FILTER (WHERE severity = 'high' AND created_at >= NOW() - INTERVAL '30 days') AS high_severity_last_30d
  FROM public.courier_incident_events
  GROUP BY courier_id
) incidents ON incidents.courier_id = c.id;
COMMIT;
