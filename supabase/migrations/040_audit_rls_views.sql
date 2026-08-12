-- 040_audit_rls_views.sql
-- Expose safe audit views for RLS/policies (service_role only).

BEGIN;
-- Tables in public schema with RLS disabled
CREATE OR REPLACE VIEW public.audit_rls_disabled AS
SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  c.relrowsecurity AS rls_enabled
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND n.nspname = 'public'
  AND c.relrowsecurity = false
ORDER BY 1,2;
-- Tables in public schema with RLS enabled but no policies
CREATE OR REPLACE VIEW public.audit_rls_no_policies AS
SELECT
  n.nspname AS schema_name,
  c.relname AS table_name
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_policies p
  ON p.schemaname = n.nspname
 AND p.tablename = c.relname
WHERE c.relkind = 'r'
  AND n.nspname = 'public'
GROUP BY n.nspname, c.relname
HAVING COUNT(p.policyname) = 0
ORDER BY 1,2;
-- Policies that include role "public"
CREATE OR REPLACE VIEW public.audit_policies_public AS
SELECT
  schemaname,
  tablename,
  policyname,
  roles
FROM pg_policies
WHERE schemaname = 'public'
  AND roles @> ARRAY['public']::name[]
ORDER BY 1,2,3;
-- Duplicate policies (same name on same table)
CREATE OR REPLACE VIEW public.audit_policies_duplicate AS
SELECT
  schemaname,
  tablename,
  policyname,
  COUNT(*) AS count
FROM pg_policies
WHERE schemaname = 'public'
GROUP BY schemaname, tablename, policyname
HAVING COUNT(*) > 1
ORDER BY 1,2,3;
-- Lock down views to service_role only
REVOKE ALL ON TABLE public.audit_rls_disabled FROM PUBLIC;
REVOKE ALL ON TABLE public.audit_rls_no_policies FROM PUBLIC;
REVOKE ALL ON TABLE public.audit_policies_public FROM PUBLIC;
REVOKE ALL ON TABLE public.audit_policies_duplicate FROM PUBLIC;
GRANT SELECT ON TABLE public.audit_rls_disabled TO service_role;
GRANT SELECT ON TABLE public.audit_rls_no_policies TO service_role;
GRANT SELECT ON TABLE public.audit_policies_public TO service_role;
GRANT SELECT ON TABLE public.audit_policies_duplicate TO service_role;
COMMIT;
