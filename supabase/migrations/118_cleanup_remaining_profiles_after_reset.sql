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
    RAISE EXCEPTION 'Não foi possível localizar Anwar e Deligo CEO para o cleanup final.';
  END IF;

  DELETE FROM public.profiles
  WHERE id <> ALL (ARRAY[v_anwar_id, v_admin_id]::UUID[]);

  DELETE FROM auth.users
  WHERE id <> ALL (ARRAY[v_anwar_id, v_admin_id]::UUID[]);
END $$;
COMMIT;
