-- Debug view to list all triggers (including internal) on auth.users
CREATE OR REPLACE VIEW public.auth_users_triggers_all AS
SELECT
  t.tgname AS trigger_name,
  t.tgisinternal AS is_internal,
  pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'auth'
  AND c.relname = 'users';
