-- 044_refresh_withdrawal_policies.sql
-- Refresh policies on withdrawal_requests to ensure RLS audit passes.

BEGIN;
DO $$
DECLARE
  r record;
BEGIN
  IF to_regclass('public.withdrawal_requests') IS NULL THEN
    RETURN;
  END IF;

  ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY;

  -- Drop existing policies (if any)
  FOR r IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'withdrawal_requests'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.withdrawal_requests', r.policyname);
  END LOOP;

  -- Recreate policies
  CREATE POLICY withdrawal_requests_select_own ON public.withdrawal_requests
    FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
  CREATE POLICY withdrawal_requests_insert_own ON public.withdrawal_requests
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id OR public.is_admin());
  CREATE POLICY withdrawal_requests_update_own ON public.withdrawal_requests
    FOR UPDATE TO authenticated USING (auth.uid() = user_id OR public.is_admin())
    WITH CHECK (auth.uid() = user_id OR public.is_admin());
  CREATE POLICY withdrawal_requests_service_all ON public.withdrawal_requests
    FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
COMMIT;
