BEGIN;
DO $$
DECLARE
  v_user_ids UUID[];
BEGIN
  SELECT COALESCE(array_agg(id), ARRAY[]::uuid[]) INTO v_user_ids
  FROM auth.users;

  IF to_regclass('public.couriers') IS NOT NULL THEN
    DELETE FROM public.couriers
    WHERE id <> ALL (v_user_ids);
  END IF;

  IF to_regclass('public.restaurants') IS NOT NULL THEN
    DELETE FROM public.restaurants
    WHERE owner_id <> ALL (v_user_ids);
  END IF;

  IF to_regclass('public.profiles') IS NOT NULL THEN
    DELETE FROM public.profiles
    WHERE id <> ALL (v_user_ids);
  END IF;

  IF to_regclass('public.push_notifications') IS NOT NULL THEN
    DELETE FROM public.push_notifications
    WHERE user_id <> ALL (v_user_ids);
  END IF;
END $$;
COMMIT;
