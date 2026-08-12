-- Debug view to inspect app trigger function definitions
CREATE OR REPLACE VIEW public.app_trigger_functions AS
SELECT
  n.nspname AS schema,
  p.proname AS function_name,
  pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'app'
  AND p.proname IN ('audit_trigger','admin_audit_trigger');
