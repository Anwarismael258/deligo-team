BEGIN;
DO $$
DECLARE
  v_bad_user_ids UUID[];
  v_bad_wallet_ids UUID[] := ARRAY[]::UUID[];
BEGIN
  SELECT COALESCE(array_agg(id), ARRAY[]::UUID[])
  INTO v_bad_user_ids
  FROM public.profiles
  WHERE regexp_replace(COALESCE(phone, ''), '[^0-9]', '', 'g') LIKE '%825262599';

  IF array_length(v_bad_user_ids, 1) IS NULL THEN
    RETURN;
  END IF;

  IF to_regclass('public.wallets') IS NOT NULL THEN
    SELECT COALESCE(array_agg(id), ARRAY[]::UUID[])
    INTO v_bad_wallet_ids
    FROM public.wallets
    WHERE user_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.kyc_submissions') IS NOT NULL THEN
    DELETE FROM public.kyc_submissions
    WHERE user_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.push_notifications') IS NOT NULL THEN
    DELETE FROM public.push_notifications
    WHERE user_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.admin_actions_log') IS NOT NULL THEN
    DELETE FROM public.admin_actions_log
    WHERE user_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.verification_scores') IS NOT NULL THEN
    DELETE FROM public.verification_scores
    WHERE user_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.wallet_deposits') IS NOT NULL THEN
    DELETE FROM public.wallet_deposits
    WHERE wallet_id = ANY(v_bad_wallet_ids);
  END IF;

  IF to_regclass('public.wallet_ledger') IS NOT NULL THEN
    DELETE FROM public.wallet_ledger
    WHERE wallet_id = ANY(v_bad_wallet_ids);
  END IF;

  IF to_regclass('public.restaurants') IS NOT NULL THEN
    DELETE FROM public.restaurants
    WHERE owner_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.couriers') IS NOT NULL THEN
    DELETE FROM public.couriers
    WHERE id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.wallets') IS NOT NULL THEN
    DELETE FROM public.wallets
    WHERE id = ANY(v_bad_wallet_ids)
       OR user_id = ANY(v_bad_user_ids);
  END IF;

  DELETE FROM public.profiles
  WHERE id = ANY(v_bad_user_ids);

  DELETE FROM auth.users
  WHERE id = ANY(v_bad_user_ids);
END $$;
COMMIT;
