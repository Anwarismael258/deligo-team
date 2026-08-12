BEGIN;
ALTER TABLE IF EXISTS public.profiles
  ADD COLUMN IF NOT EXISTS verification_score INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS auto_verified BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS approval_submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approval_sla_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS verification_last_scored_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS verification_decision_source TEXT DEFAULT 'manual';
ALTER TABLE IF EXISTS public.profiles
  DROP CONSTRAINT IF EXISTS profiles_verification_score_range;
ALTER TABLE IF EXISTS public.profiles
  ADD CONSTRAINT profiles_verification_score_range
  CHECK (verification_score BETWEEN 0 AND 100);
CREATE TABLE IF NOT EXISTS public.verification_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
  reason TEXT NOT NULL,
  breakdown JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.admin_actions_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  reason TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_verification_scores_user_created_at
  ON public.verification_scores(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_actions_log_user_created_at
  ON public.admin_actions_log(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_profiles_kyc_status_sla
  ON public.profiles(kyc_status, approval_sla_deadline)
  WHERE role IN ('restaurant', 'courier');
ALTER TABLE public.verification_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_actions_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS verification_scores_select_self ON public.verification_scores;
CREATE POLICY verification_scores_select_self
ON public.verification_scores
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS verification_scores_insert_admin ON public.verification_scores;
CREATE POLICY verification_scores_insert_admin
ON public.verification_scores
FOR INSERT TO authenticated
WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS verification_scores_service_all ON public.verification_scores;
CREATE POLICY verification_scores_service_all
ON public.verification_scores
FOR ALL TO service_role
USING (true)
WITH CHECK (true);
DROP POLICY IF EXISTS admin_actions_log_select_self ON public.admin_actions_log;
CREATE POLICY admin_actions_log_select_self
ON public.admin_actions_log
FOR SELECT TO authenticated
USING (user_id = auth.uid() OR admin_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS admin_actions_log_insert_admin ON public.admin_actions_log;
CREATE POLICY admin_actions_log_insert_admin
ON public.admin_actions_log
FOR INSERT TO authenticated
WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS admin_actions_log_service_all ON public.admin_actions_log;
CREATE POLICY admin_actions_log_service_all
ON public.admin_actions_log
FOR ALL TO service_role
USING (true)
WITH CHECK (true);
CREATE OR REPLACE FUNCTION public.calculate_profile_verification_score(
  p_user_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_profile public.profiles%ROWTYPE;
  v_email_confirmed_at TIMESTAMPTZ;
  v_score INTEGER := 0;
  v_breakdown JSONB := '{}'::jsonb;
  v_docs JSONB := '{}'::jsonb;
  v_required_docs TEXT[];
  v_all_required_present BOOLEAN := TRUE;
  v_doc_key TEXT;
BEGIN
  SELECT *
  INTO v_profile
  FROM public.profiles
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  v_docs := COALESCE(v_profile.kyc_docs, '{}'::jsonb);

  IF v_profile.role = 'courier' THEN
    v_required_docs := ARRAY['ownerPhoto', 'license', 'livret', 'vehiclePhoto'];
  ELSIF v_profile.role = 'restaurant' THEN
    v_required_docs := ARRAY['biFront', 'biBack', 'selfie'];
  ELSE
    v_required_docs := ARRAY[]::TEXT[];
  END IF;

  FOREACH v_doc_key IN ARRAY v_required_docs LOOP
    IF COALESCE(NULLIF(v_docs ->> v_doc_key, ''), '') = '' THEN
      v_all_required_present := FALSE;
    END IF;
  END LOOP;

  IF v_all_required_present AND array_length(v_required_docs, 1) IS NOT NULL THEN
    v_score := v_score + 40;
    v_breakdown := v_breakdown || jsonb_build_object('documents_valid', 40);
  END IF;

  IF COALESCE(NULLIF(v_profile.full_name, ''), '') <> '' THEN
    v_score := v_score + 20;
    v_breakdown := v_breakdown || jsonb_build_object('name_present', 20);
  END IF;

  IF (
    (v_profile.role = 'restaurant' AND COALESCE(NULLIF(v_docs ->> 'selfie', ''), '') <> '') OR
    (v_profile.role = 'courier' AND COALESCE(NULLIF(v_docs ->> 'ownerPhoto', ''), '') <> '')
  ) THEN
    v_score := v_score + 20;
    v_breakdown := v_breakdown || jsonb_build_object('selfie_match_proxy', 20);
  END IF;

  IF COALESCE(NULLIF(v_profile.phone, ''), '') <> '' THEN
    v_score := v_score + 10;
    v_breakdown := v_breakdown || jsonb_build_object('phone_present', 10);
  END IF;

  SELECT au.email_confirmed_at
  INTO v_email_confirmed_at
  FROM auth.users au
  WHERE au.id = p_user_id;

  IF v_email_confirmed_at IS NOT NULL THEN
    v_score := v_score + 10;
    v_breakdown := v_breakdown || jsonb_build_object('email_verified', 10);
  END IF;

  v_score := LEAST(GREATEST(v_score, 0), 100);

  UPDATE public.profiles
  SET
    verification_score = v_score,
    verification_last_scored_at = now(),
    updated_at = now()
  WHERE id = p_user_id;

  INSERT INTO public.verification_scores (user_id, score, reason, breakdown)
  VALUES (
    p_user_id,
    v_score,
    'Automatic verification score calculation',
    v_breakdown
  );

  RETURN v_score;
END;
$$;
CREATE OR REPLACE FUNCTION public.apply_profile_auto_verification(
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_profile public.profiles%ROWTYPE;
  v_score INTEGER := 0;
  v_reason TEXT := NULL;
  v_status TEXT := 'pending';
BEGIN
  SELECT *
  INTO v_profile
  FROM public.profiles
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'profile_not_found');
  END IF;

  IF v_profile.role NOT IN ('restaurant', 'courier') THEN
    RETURN jsonb_build_object(
      'success', true,
      'status', COALESCE(v_profile.kyc_status, 'approved'),
      'score', COALESCE(v_profile.verification_score, 0),
      'auto_verified', COALESCE(v_profile.auto_verified, false)
    );
  END IF;

  v_score := public.calculate_profile_verification_score(p_user_id);

  IF v_score >= 80 THEN
    v_status := 'approved';
    UPDATE public.profiles
    SET
      kyc_status = 'approved',
      kyc_completed = TRUE,
      auto_verified = TRUE,
      kyc_rejection_reason = NULL,
      kyc_rejected_at = NULL,
      verification_decision_source = 'auto',
      updated_at = now()
    WHERE id = p_user_id;

    INSERT INTO public.admin_actions_log (admin_id, user_id, action, reason, metadata)
    VALUES (
      NULL,
      p_user_id,
      'auto_approved',
      'Automatic approval based on verification score',
      jsonb_build_object('score', v_score)
    );

    PERFORM public.create_app_notification(
      p_user_id,
      'kyc_approved',
      'Conta aprovada',
      'A sua conta foi aprovada automaticamente e ja pode entrar no app.',
      'OPEN_APPROVED_ACCOUNT',
      p_user_id::text,
      'HIGH',
      'kyc',
      jsonb_build_object('user_id', p_user_id, 'score', v_score, 'source', 'auto')
    );
  ELSIF v_score < 50 THEN
    v_status := 'rejected';
    v_reason := 'Baixa pontuacao automatica';
    UPDATE public.profiles
    SET
      kyc_status = 'rejected',
      kyc_completed = FALSE,
      auto_verified = FALSE,
      kyc_rejection_reason = v_reason,
      kyc_rejected_at = now(),
      verification_decision_source = 'auto',
      updated_at = now()
    WHERE id = p_user_id;

    INSERT INTO public.admin_actions_log (admin_id, user_id, action, reason, metadata)
    VALUES (
      NULL,
      p_user_id,
      'auto_rejected',
      v_reason,
      jsonb_build_object('score', v_score)
    );

    PERFORM public.create_app_notification(
      p_user_id,
      'kyc_rejected',
      'Conta rejeitada',
      'A verificacao automatica rejeitou os documentos. Entre no app para rever o motivo e reenviar.',
      'OPEN_KYC_PENDING',
      p_user_id::text,
      'HIGH',
      'kyc',
      jsonb_build_object('user_id', p_user_id, 'score', v_score, 'source', 'auto')
    );

    UPDATE public.restaurants
    SET is_open = FALSE, updated_at = now()
    WHERE owner_id = p_user_id;
  ELSE
    v_status := 'pending';
    UPDATE public.profiles
    SET
      kyc_status = 'pending',
      kyc_completed = FALSE,
      auto_verified = FALSE,
      verification_decision_source = 'manual',
      updated_at = now()
    WHERE id = p_user_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', v_status,
    'score', v_score,
    'auto_verified', v_status = 'approved'
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.prepare_profile_verification(
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_profile public.profiles%ROWTYPE;
  v_result JSONB;
BEGIN
  SELECT *
  INTO v_profile
  FROM public.profiles
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'profile_not_found');
  END IF;

  IF v_profile.role NOT IN ('restaurant', 'courier') THEN
    RETURN jsonb_build_object('success', true, 'status', COALESCE(v_profile.kyc_status, 'approved'));
  END IF;

  UPDATE public.profiles
  SET
    approval_submitted_at = COALESCE(approval_submitted_at, now()),
    approval_sla_deadline = COALESCE(approval_sla_deadline, now() + interval '24 hours'),
    kyc_status = 'pending',
    kyc_completed = FALSE,
    auto_verified = FALSE,
    verification_decision_source = 'manual',
    updated_at = now()
  WHERE id = p_user_id;

  v_result := public.apply_profile_auto_verification(p_user_id);
  RETURN v_result;
END;
$$;
CREATE OR REPLACE FUNCTION public.enforce_review_required_profiles()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.role IN ('restaurant', 'courier') THEN
    NEW.kyc_status := COALESCE(NEW.kyc_status, 'pending');
    IF NEW.kyc_status = 'approved' THEN
      NEW.kyc_status := 'pending';
    END IF;
    NEW.kyc_completed := FALSE;
    NEW.auto_verified := COALESCE(NEW.auto_verified, FALSE);
    NEW.approval_submitted_at := COALESCE(NEW.approval_submitted_at, now());
    NEW.approval_sla_deadline := COALESCE(NEW.approval_sla_deadline, NEW.approval_submitted_at + interval '24 hours');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_review_required_profiles ON public.profiles;
CREATE TRIGGER trg_enforce_review_required_profiles
BEFORE INSERT ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.enforce_review_required_profiles();
CREATE OR REPLACE FUNCTION public.on_profile_verification_docs_changed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  IF NEW.role IN ('restaurant', 'courier')
     AND COALESCE(jsonb_typeof(NEW.kyc_docs), '') = 'object'
     AND jsonb_object_length(COALESCE(NEW.kyc_docs, '{}'::jsonb)) > 0
     AND (
       TG_OP = 'INSERT'
       OR NEW.kyc_docs IS DISTINCT FROM OLD.kyc_docs
       OR NEW.phone IS DISTINCT FROM OLD.phone
       OR NEW.full_name IS DISTINCT FROM OLD.full_name
     ) THEN
    PERFORM public.prepare_profile_verification(NEW.id);
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_profile_verification_docs_changed ON public.profiles;
CREATE TRIGGER trg_profile_verification_docs_changed
AFTER INSERT OR UPDATE OF kyc_docs, phone, full_name ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.on_profile_verification_docs_changed();
CREATE OR REPLACE FUNCTION public.enforce_restaurant_open_state_for_unapproved_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_status TEXT;
BEGIN
  SELECT kyc_status
  INTO v_owner_status
  FROM public.profiles
  WHERE id = NEW.owner_id;

  IF COALESCE(v_owner_status, 'pending') <> 'approved' THEN
    NEW.is_open := FALSE;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_restaurant_open_state_for_unapproved_owner ON public.restaurants;
CREATE TRIGGER trg_enforce_restaurant_open_state_for_unapproved_owner
BEFORE INSERT OR UPDATE OF owner_id, is_open ON public.restaurants
FOR EACH ROW
EXECUTE FUNCTION public.enforce_restaurant_open_state_for_unapproved_owner();
UPDATE public.profiles
SET
  approval_submitted_at = COALESCE(approval_submitted_at, now()),
  approval_sla_deadline = COALESCE(approval_sla_deadline, now() + interval '24 hours'),
  kyc_status = COALESCE(NULLIF(kyc_status, ''), 'pending'),
  kyc_completed = FALSE
WHERE role IN ('restaurant', 'courier')
  AND COALESCE(kyc_status, 'pending') <> 'approved';
COMMIT;
