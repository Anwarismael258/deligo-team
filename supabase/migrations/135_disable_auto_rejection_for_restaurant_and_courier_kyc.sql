BEGIN;
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
    v_required_docs := ARRAY['foto', 'bi_frente', 'bi_tras', 'selfie'];
  ELSIF v_profile.role = 'restaurant' THEN
    v_required_docs := ARRAY['foto_loja', 'bi_frente', 'bi_tras', 'selfie'];
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
    v_breakdown := v_breakdown || jsonb_build_object('documents_present', 40);
  END IF;

  IF COALESCE(NULLIF(v_profile.full_name, ''), '') <> '' THEN
    v_score := v_score + 20;
    v_breakdown := v_breakdown || jsonb_build_object('name_present', 20);
  END IF;

  IF (
    (v_profile.role = 'restaurant' AND COALESCE(NULLIF(v_docs ->> 'selfie', ''), '') <> '') OR
    (v_profile.role = 'courier' AND COALESCE(NULLIF(v_docs ->> 'foto', ''), '') <> '')
  ) THEN
    v_score := v_score + 20;
    v_breakdown := v_breakdown || jsonb_build_object('photo_present', 20);
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
    'Manual review scoring snapshot',
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

  UPDATE public.profiles
  SET
    kyc_status = 'pending',
    kyc_completed = FALSE,
    auto_verified = FALSE,
    kyc_rejection_reason = NULL,
    kyc_rejected_at = NULL,
    verification_decision_source = 'manual',
    updated_at = now()
  WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'status', 'pending',
    'score', v_score,
    'auto_verified', false
  );
END;
$$;
UPDATE public.profiles
SET
  kyc_status = 'pending',
  kyc_completed = FALSE,
  auto_verified = FALSE,
  kyc_rejection_reason = NULL,
  kyc_rejected_at = NULL,
  verification_decision_source = 'manual',
  updated_at = now()
WHERE role IN ('restaurant', 'courier')
  AND verification_decision_source = 'auto'
  AND kyc_status = 'rejected';
COMMIT;
