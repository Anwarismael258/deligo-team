-- Remove legacy public triggers on auth.users and keep only the consolidated
-- bootstrap trigger. Older trigger chains could run in the wrong order and
-- fail staff account creation before public.users existed.

DO $$
DECLARE
  trigger_row RECORD;
BEGIN
  FOR trigger_row IN
    SELECT t.tgname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace table_ns ON table_ns.oid = c.relnamespace
    JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace fn_ns ON fn_ns.oid = p.pronamespace
    WHERE table_ns.nspname = 'auth'
      AND c.relname = 'users'
      AND NOT t.tgisinternal
      AND fn_ns.nspname = 'public'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON auth.users', trigger_row.tgname);
  END LOOP;
END $$;
DROP TRIGGER IF EXISTS trg_bootstrap_new_auth_user ON auth.users;
CREATE TRIGGER trg_bootstrap_new_auth_user
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.bootstrap_new_auth_user();
