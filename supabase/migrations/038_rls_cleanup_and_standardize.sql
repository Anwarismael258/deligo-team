-- 038_rls_cleanup_and_standardize.sql
-- Clean, secure, and standardize RLS policies for core tables.
-- Safe to run multiple times. Uses conditional checks for table/column existence.

BEGIN;
-- Helper: admin check from JWT or service_role
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
-- Utility: drop all policies for a given table if it exists
DO $$
DECLARE
  t text;
  r record;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'profiles',
    'customers',
    'menus',
    'alerts_log',
    'gamification_logs',
    'leaderboards',
    'refunds',
    'cron_runs',
    'delivery_zones',
    'restaurant_members',
    'push_notifications',
    'reviews',
    'zone_order_stats'
  ])
  LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      FOR r IN
        SELECT policyname
        FROM pg_policies
        WHERE schemaname = 'public' AND tablename = t
      LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', r.policyname, t);
      END LOOP;
    END IF;
  END LOOP;
END $$;
-- PROFILES: minimal, clean policies
DO $$
DECLARE
  owner_cond text;
  has_id boolean;
  has_auth_id boolean;
BEGIN
  IF to_regclass('public.profiles') IS NULL THEN
    RETURN;
  END IF;

  ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'id'
  ) INTO has_id;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'auth_id'
  ) INTO has_auth_id;

  IF has_id THEN
    owner_cond := 'auth.uid() = id';
  ELSIF has_auth_id THEN
    owner_cond := 'auth.uid() = auth_id';
  ELSE
    owner_cond := 'false';
  END IF;

  EXECUTE format(
    'CREATE POLICY profiles_select_own ON public.profiles FOR SELECT USING (%s OR public.is_admin())',
    owner_cond
  );
  EXECUTE format(
    'CREATE POLICY profiles_insert_own ON public.profiles FOR INSERT WITH CHECK (%s OR public.is_admin())',
    owner_cond
  );
  EXECUTE format(
    'CREATE POLICY profiles_update_own ON public.profiles FOR UPDATE USING (%s OR public.is_admin()) WITH CHECK (%s OR public.is_admin())',
    owner_cond, owner_cond
  );
END $$;
-- CUSTOMERS: own rows + admin
DO $$
DECLARE
  cond text;
BEGIN
  IF to_regclass('public.customers') IS NULL THEN
    RETURN;
  END IF;
  ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'customers' AND column_name = 'user_id'
  ) THEN
    cond := 'auth.uid() = user_id';
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'customers' AND column_name = 'auth_id'
  ) THEN
    cond := 'auth.uid() = auth_id';
  ELSE
    cond := 'false';
  END IF;

  EXECUTE format(
    'CREATE POLICY customers_select_own ON public.customers FOR SELECT USING (%s OR public.is_admin())',
    cond
  );
  EXECUTE format(
    'CREATE POLICY customers_insert_own ON public.customers FOR INSERT WITH CHECK (%s OR public.is_admin())',
    cond
  );
  EXECUTE format(
    'CREATE POLICY customers_update_own ON public.customers FOR UPDATE USING (%s OR public.is_admin()) WITH CHECK (%s OR public.is_admin())',
    cond, cond
  );
  EXECUTE 'CREATE POLICY customers_admin_all ON public.customers FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin())';
END $$;
-- MENUS: public read, owner write, admin full
DO $$
BEGIN
  IF to_regclass('public.menus') IS NULL THEN
    RETURN;
  END IF;
  ALTER TABLE public.menus ENABLE ROW LEVEL SECURITY;

  CREATE POLICY menus_select_public ON public.menus FOR SELECT TO anon, authenticated USING (true);

  IF to_regclass('public.restaurants') IS NOT NULL AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'menus' AND column_name = 'restaurant_id'
  ) THEN
    CREATE POLICY menus_write_owner ON public.menus
      FOR ALL TO authenticated
      USING (
        restaurant_id IN (SELECT id FROM public.restaurants WHERE owner_id = auth.uid())
      )
      WITH CHECK (
        restaurant_id IN (SELECT id FROM public.restaurants WHERE owner_id = auth.uid())
      );
  END IF;

  CREATE POLICY menus_admin_all ON public.menus FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
END $$;
-- ALERTS_LOG: service/admin only
DO $$
BEGIN
  IF to_regclass('public.alerts_log') IS NULL THEN
    RETURN;
  END IF;
  ALTER TABLE public.alerts_log ENABLE ROW LEVEL SECURITY;
  CREATE POLICY alerts_log_admin_all ON public.alerts_log
    FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
END $$;
-- GAMIFICATION_LOGS: select own, service/admin write
DO $$
BEGIN
  IF to_regclass('public.gamification_logs') IS NULL THEN
    RETURN;
  END IF;
  ALTER TABLE public.gamification_logs ENABLE ROW LEVEL SECURITY;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'gamification_logs' AND column_name = 'user_id'
  ) THEN
    CREATE POLICY gamification_select_own ON public.gamification_logs
      FOR SELECT USING (auth.uid() = user_id OR public.is_admin());
  END IF;

  CREATE POLICY gamification_admin_all ON public.gamification_logs
    FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
END $$;
-- LEADERBOARDS: public read, admin write
DO $$
BEGIN
  IF to_regclass('public.leaderboards') IS NULL THEN
    RETURN;
  END IF;
  ALTER TABLE public.leaderboards ENABLE ROW LEVEL SECURITY;
  CREATE POLICY leaderboards_select_public ON public.leaderboards FOR SELECT TO anon, authenticated USING (true);
  CREATE POLICY leaderboards_admin_all ON public.leaderboards FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
END $$;
-- REFUNDS: service/admin only, optional own view if user_id exists
DO $$
BEGIN
  IF to_regclass('public.refunds') IS NULL THEN
    RETURN;
  END IF;
  ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'refunds' AND column_name = 'user_id'
  ) THEN
    CREATE POLICY refunds_select_own ON public.refunds
      FOR SELECT USING (auth.uid() = user_id OR public.is_admin());
  END IF;

  CREATE POLICY refunds_admin_all ON public.refunds
    FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
END $$;
-- CRON_RUNS: service/admin only
DO $$
BEGIN
  IF to_regclass('public.cron_runs') IS NULL THEN
    RETURN;
  END IF;
  ALTER TABLE public.cron_runs ENABLE ROW LEVEL SECURITY;
  CREATE POLICY cron_runs_admin_all ON public.cron_runs
    FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
END $$;
-- DELIVERY_ZONES: public read, admin write
DO $$
BEGIN
  IF to_regclass('public.delivery_zones') IS NULL THEN
    RETURN;
  END IF;
  ALTER TABLE public.delivery_zones ENABLE ROW LEVEL SECURITY;
  CREATE POLICY delivery_zones_select_public ON public.delivery_zones FOR SELECT TO anon, authenticated USING (true);
  CREATE POLICY delivery_zones_admin_all ON public.delivery_zones
    FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
END $$;
-- RESTAURANT_MEMBERS: member or owner can read, owner manages
DO $$
BEGIN
  IF to_regclass('public.restaurant_members') IS NULL THEN
    RETURN;
  END IF;
  ALTER TABLE public.restaurant_members ENABLE ROW LEVEL SECURITY;

  IF to_regclass('public.restaurants') IS NOT NULL AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'restaurant_members' AND column_name = 'restaurant_id'
  ) THEN
    CREATE POLICY restaurant_members_select ON public.restaurant_members
      FOR SELECT USING (
        (EXISTS (
          SELECT 1 FROM public.restaurants r
          WHERE r.id = restaurant_id AND r.owner_id = auth.uid()
        ))
        OR
        (EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'restaurant_members' AND column_name = 'user_id'
        ) AND auth.uid() = user_id)
        OR public.is_admin()
      );

    CREATE POLICY restaurant_members_owner_manage ON public.restaurant_members
      FOR ALL TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.restaurants r
          WHERE r.id = restaurant_id AND r.owner_id = auth.uid()
        ) OR public.is_admin()
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.restaurants r
          WHERE r.id = restaurant_id AND r.owner_id = auth.uid()
        ) OR public.is_admin()
      );
  END IF;
END $$;
-- PUSH_NOTIFICATIONS: user can read/update own, service/admin can write
DO $$
BEGIN
  IF to_regclass('public.push_notifications') IS NULL THEN
    RETURN;
  END IF;
  ALTER TABLE public.push_notifications ENABLE ROW LEVEL SECURITY;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'push_notifications' AND column_name = 'user_id'
  ) THEN
    CREATE POLICY push_notifications_select_own ON public.push_notifications
      FOR SELECT USING (auth.uid() = user_id OR public.is_admin());

    CREATE POLICY push_notifications_update_own ON public.push_notifications
      FOR UPDATE USING (auth.uid() = user_id OR public.is_admin())
      WITH CHECK (auth.uid() = user_id OR public.is_admin());
  END IF;

  CREATE POLICY push_notifications_admin_all ON public.push_notifications
    FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
END $$;
-- REVIEWS: public read, own write
DO $$
DECLARE
  reviewer_col text;
BEGIN
  IF to_regclass('public.reviews') IS NULL THEN
    RETURN;
  END IF;
  ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

  CREATE POLICY reviews_select_public ON public.reviews FOR SELECT TO anon, authenticated USING (true);

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'reviews' AND column_name = 'reviewer_id'
  ) THEN
    reviewer_col := 'reviewer_id';
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'reviews' AND column_name = 'user_id'
  ) THEN
    reviewer_col := 'user_id';
  ELSE
    reviewer_col := NULL;
  END IF;

  IF reviewer_col IS NOT NULL THEN
    EXECUTE format(
      'CREATE POLICY reviews_insert_own ON public.reviews FOR INSERT WITH CHECK (auth.uid() = %I OR public.is_admin())',
      reviewer_col
    );
    EXECUTE format(
      'CREATE POLICY reviews_update_own ON public.reviews FOR UPDATE USING (auth.uid() = %I OR public.is_admin()) WITH CHECK (auth.uid() = %I OR public.is_admin())',
      reviewer_col, reviewer_col
    );
    EXECUTE format(
      'CREATE POLICY reviews_delete_own ON public.reviews FOR DELETE USING (auth.uid() = %I OR public.is_admin())',
      reviewer_col
    );
  END IF;
END $$;
-- ZONE_ORDER_STATS: public read, admin write
DO $$
BEGIN
  IF to_regclass('public.zone_order_stats') IS NULL THEN
    RETURN;
  END IF;
  ALTER TABLE public.zone_order_stats ENABLE ROW LEVEL SECURITY;
  CREATE POLICY zone_order_stats_select_public ON public.zone_order_stats FOR SELECT TO anon, authenticated USING (true);
  CREATE POLICY zone_order_stats_admin_all ON public.zone_order_stats
    FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
END $$;
COMMIT;
