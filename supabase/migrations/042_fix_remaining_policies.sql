-- 042_fix_remaining_policies.sql
-- Fix remaining tables from audit: add RLS policies for payment_transactions, ratings, transactions, user_roles.

BEGIN;
-- Ensure helper exists
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT
    auth.role() = 'service_role'
    OR COALESCE(
      auth.jwt() ->> 'role',
      auth.jwt() -> 'app_metadata' ->> 'role',
      auth.jwt() -> 'user_metadata' ->> 'role'
    ) = 'admin';
$$;
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC;
-- Drop policies for these tables if any
DO $$
DECLARE
  t text;
  r record;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'payment_transactions','ratings','transactions','user_roles'
  ])
  LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      FOR r IN
        SELECT policyname FROM pg_policies
        WHERE schemaname = 'public' AND tablename = t
      LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', r.policyname, t);
      END LOOP;
    END IF;
  END LOOP;
END $$;
-- payment_transactions: user read own, service_role all
DO $$
BEGIN
  IF to_regclass('public.payment_transactions') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='payment_transactions' AND column_name='user_id') THEN
    CREATE POLICY payment_transactions_select_own ON public.payment_transactions
      FOR SELECT TO authenticated
      USING (auth.uid() = user_id OR public.is_admin());
  ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='payment_transactions' AND column_name='customer_id') THEN
    CREATE POLICY payment_transactions_select_own ON public.payment_transactions
      FOR SELECT TO authenticated
      USING (auth.uid() = customer_id OR public.is_admin());
  END IF;
  CREATE POLICY payment_transactions_service_all ON public.payment_transactions
    FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
-- ratings: public read, own write
DO $$
DECLARE reviewer_col text;
BEGIN
  IF to_regclass('public.ratings') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.ratings ENABLE ROW LEVEL SECURITY;
  CREATE POLICY ratings_public_read ON public.ratings FOR SELECT TO anon, authenticated USING (true);
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='ratings' AND column_name='reviewer_id') THEN
    reviewer_col := 'reviewer_id';
  ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='ratings' AND column_name='user_id') THEN
    reviewer_col := 'user_id';
  ELSE
    reviewer_col := NULL;
  END IF;
  IF reviewer_col IS NOT NULL THEN
    EXECUTE format('CREATE POLICY ratings_insert_own ON public.ratings FOR INSERT TO authenticated WITH CHECK (auth.uid() = %I OR public.is_admin())', reviewer_col);
    EXECUTE format('CREATE POLICY ratings_update_own ON public.ratings FOR UPDATE TO authenticated USING (auth.uid() = %I OR public.is_admin()) WITH CHECK (auth.uid() = %I OR public.is_admin())', reviewer_col, reviewer_col);
    EXECUTE format('CREATE POLICY ratings_delete_own ON public.ratings FOR DELETE TO authenticated USING (auth.uid() = %I OR public.is_admin())', reviewer_col);
  END IF;
  CREATE POLICY ratings_service_all ON public.ratings FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
-- transactions: ledger-style; allow own view if possible, service_role all
DO $$
BEGIN
  IF to_regclass('public.transactions') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='transactions' AND column_name='user_id') THEN
    CREATE POLICY transactions_select_own ON public.transactions
      FOR SELECT TO authenticated
      USING (auth.uid() = user_id OR public.is_admin());
  ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='transactions' AND column_name='wallet_id') THEN
    CREATE POLICY transactions_select_own ON public.transactions
      FOR SELECT TO authenticated
      USING (wallet_id IN (SELECT id FROM public.wallets WHERE user_id = auth.uid()) OR public.is_admin());
  END IF;

  CREATE POLICY transactions_no_update ON public.transactions FOR UPDATE TO authenticated USING (false);
  CREATE POLICY transactions_no_delete ON public.transactions FOR DELETE TO authenticated USING (false);
  CREATE POLICY transactions_service_all ON public.transactions FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
-- user_roles: service_role only
DO $$
BEGIN
  IF to_regclass('public.user_roles') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
  CREATE POLICY user_roles_service_all ON public.user_roles
    FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
COMMIT;
