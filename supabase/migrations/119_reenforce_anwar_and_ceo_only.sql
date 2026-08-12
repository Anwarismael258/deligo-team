BEGIN;
DO $$
DECLARE
  v_anwar_id UUID;
  v_admin_id UUID;
BEGIN
  SELECT id
  INTO v_anwar_id
  FROM auth.users
  WHERE LOWER(email) = 'anwarismael258@gmail.com'
  LIMIT 1;

  SELECT id
  INTO v_admin_id
  FROM auth.users
  WHERE LOWER(email) = 'deligoentregas@gmail.com'
  LIMIT 1;

  IF v_anwar_id IS NULL OR v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Nao foi possivel localizar Anwar e Deligo CEO para o cleanup.';
  END IF;

  IF to_regclass('public.notifications') IS NOT NULL THEN
    DELETE FROM public.notifications
    WHERE user_id <> ALL (ARRAY[v_anwar_id, v_admin_id]::UUID[]);
  END IF;

  IF to_regclass('public.push_notifications') IS NOT NULL THEN
    DELETE FROM public.push_notifications
    WHERE user_id <> ALL (ARRAY[v_anwar_id, v_admin_id]::UUID[]);
  END IF;
END $$;
COMMIT;
