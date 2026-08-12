-- 041_security_audit_fixes.sql
-- Fix remaining audit findings: remove PUBLIC policies, add missing policies, and enable RLS where needed.
-- Uses conditional checks to avoid errors if tables/columns do not exist.

BEGIN;
-- Helper: ensure admin/service role can always access
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
-- Helper: drop all policies for a table
DO $$
DECLARE
  t text;
  r record;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'profiles','customers','menus','menu_items','restaurants','delivery_zones','reviews',
    'favorites','user_addresses','push_notifications','wallets','wallet_deposits','payment_splits',
    'webhook_events','messages','chat_messages','chats','chat_members','courier_locations',
    'kyc_requests','ratings','transactions','payment_transactions','points_transactions',
    'achievements','streaks','user_missions','user_roles'
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
-- PROFILES
DO $$
DECLARE owner_cond text;
BEGIN
  IF to_regclass('public.profiles') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='id') THEN
    owner_cond := 'auth.uid() = id';
  ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='auth_id') THEN
    owner_cond := 'auth.uid() = auth_id';
  ELSE
    owner_cond := 'false';
  END IF;
  EXECUTE format('CREATE POLICY profiles_select_own ON public.profiles FOR SELECT TO authenticated USING (%s OR public.is_admin())', owner_cond);
  EXECUTE format('CREATE POLICY profiles_insert_own ON public.profiles FOR INSERT TO authenticated WITH CHECK (%s OR public.is_admin())', owner_cond);
  EXECUTE format('CREATE POLICY profiles_update_own ON public.profiles FOR UPDATE TO authenticated USING (%s OR public.is_admin()) WITH CHECK (%s OR public.is_admin())', owner_cond, owner_cond);
  CREATE POLICY profiles_service_all ON public.profiles FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
-- CUSTOMERS
DO $$
DECLARE owner_cond text;
BEGIN
  IF to_regclass('public.customers') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='customers' AND column_name='user_id') THEN
    owner_cond := 'auth.uid() = user_id';
  ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='customers' AND column_name='auth_id') THEN
    owner_cond := 'auth.uid() = auth_id';
  ELSE
    owner_cond := 'false';
  END IF;
  EXECUTE format('CREATE POLICY customers_select_own ON public.customers FOR SELECT TO authenticated USING (%s OR public.is_admin())', owner_cond);
  EXECUTE format('CREATE POLICY customers_insert_own ON public.customers FOR INSERT TO authenticated WITH CHECK (%s OR public.is_admin())', owner_cond);
  EXECUTE format('CREATE POLICY customers_update_own ON public.customers FOR UPDATE TO authenticated USING (%s OR public.is_admin()) WITH CHECK (%s OR public.is_admin())', owner_cond, owner_cond);
  CREATE POLICY customers_service_all ON public.customers FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
-- MENUS + MENU_ITEMS (public read, owner write)
DO $$
BEGIN
  IF to_regclass('public.menus') IS NOT NULL THEN
    ALTER TABLE public.menus ENABLE ROW LEVEL SECURITY;
    CREATE POLICY menus_select_public ON public.menus FOR SELECT TO anon, authenticated USING (true);
    IF to_regclass('public.restaurants') IS NOT NULL AND EXISTS (
      SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='menus' AND column_name='restaurant_id'
    ) THEN
      CREATE POLICY menus_owner_write ON public.menus
        FOR ALL TO authenticated
        USING (restaurant_id IN (SELECT id FROM public.restaurants WHERE owner_id = auth.uid()))
        WITH CHECK (restaurant_id IN (SELECT id FROM public.restaurants WHERE owner_id = auth.uid()));
    END IF;
    CREATE POLICY menus_service_all ON public.menus FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;

  IF to_regclass('public.menu_items') IS NOT NULL THEN
    ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;
    CREATE POLICY menu_items_select_public ON public.menu_items FOR SELECT TO anon, authenticated USING (true);
    IF to_regclass('public.restaurants') IS NOT NULL AND EXISTS (
      SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='menu_items' AND column_name='restaurant_id'
    ) THEN
      CREATE POLICY menu_items_owner_write ON public.menu_items
        FOR ALL TO authenticated
        USING (restaurant_id IN (SELECT id FROM public.restaurants WHERE owner_id = auth.uid()))
        WITH CHECK (restaurant_id IN (SELECT id FROM public.restaurants WHERE owner_id = auth.uid()));
    END IF;
    CREATE POLICY menu_items_service_all ON public.menu_items FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
END $$;
-- RESTAURANTS (public read, owner write)
DO $$
BEGIN
  IF to_regclass('public.restaurants') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
  CREATE POLICY restaurants_select_public ON public.restaurants FOR SELECT TO anon, authenticated USING (true);
  IF EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='restaurants' AND column_name='owner_id'
  ) THEN
    CREATE POLICY restaurants_owner_write ON public.restaurants
      FOR ALL TO authenticated
      USING (owner_id = auth.uid())
      WITH CHECK (owner_id = auth.uid());
  END IF;
  CREATE POLICY restaurants_service_all ON public.restaurants FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
-- DELIVERY_ZONES (public read, admin/service write)
DO $$
BEGIN
  IF to_regclass('public.delivery_zones') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.delivery_zones ENABLE ROW LEVEL SECURITY;
  CREATE POLICY delivery_zones_select_public ON public.delivery_zones FOR SELECT TO anon, authenticated USING (true);
  CREATE POLICY delivery_zones_admin_write ON public.delivery_zones FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
  CREATE POLICY delivery_zones_service_all ON public.delivery_zones FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
-- REVIEWS (public read, owner write)
DO $$
DECLARE reviewer_col text;
BEGIN
  IF to_regclass('public.reviews') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
  CREATE POLICY reviews_select_public ON public.reviews FOR SELECT TO anon, authenticated USING (true);
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='reviews' AND column_name='reviewer_id') THEN
    reviewer_col := 'reviewer_id';
  ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='reviews' AND column_name='user_id') THEN
    reviewer_col := 'user_id';
  ELSE
    reviewer_col := NULL;
  END IF;
  IF reviewer_col IS NOT NULL THEN
    EXECUTE format('CREATE POLICY reviews_insert_own ON public.reviews FOR INSERT TO authenticated WITH CHECK (auth.uid() = %I OR public.is_admin())', reviewer_col);
    EXECUTE format('CREATE POLICY reviews_update_own ON public.reviews FOR UPDATE TO authenticated USING (auth.uid() = %I OR public.is_admin()) WITH CHECK (auth.uid() = %I OR public.is_admin())', reviewer_col, reviewer_col);
    EXECUTE format('CREATE POLICY reviews_delete_own ON public.reviews FOR DELETE TO authenticated USING (auth.uid() = %I OR public.is_admin())', reviewer_col);
  END IF;
  CREATE POLICY reviews_service_all ON public.reviews FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
-- FAVORITES / USER_ADDRESSES
DO $$
BEGIN
  IF to_regclass('public.favorites') IS NOT NULL THEN
    ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;
    CREATE POLICY favorites_select_own ON public.favorites FOR SELECT TO authenticated USING (auth.uid() = user_id);
    CREATE POLICY favorites_manage_own ON public.favorites FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    CREATE POLICY favorites_service_all ON public.favorites FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;

  IF to_regclass('public.user_addresses') IS NOT NULL THEN
    ALTER TABLE public.user_addresses ENABLE ROW LEVEL SECURITY;
    CREATE POLICY addresses_select_own ON public.user_addresses FOR SELECT TO authenticated USING (auth.uid() = user_id);
    CREATE POLICY addresses_manage_own ON public.user_addresses FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    CREATE POLICY addresses_service_all ON public.user_addresses FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
END $$;
-- PUSH_NOTIFICATIONS
DO $$
BEGIN
  IF to_regclass('public.push_notifications') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.push_notifications ENABLE ROW LEVEL SECURITY;
  CREATE POLICY push_notifications_select_own ON public.push_notifications FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
  CREATE POLICY push_notifications_update_own ON public.push_notifications FOR UPDATE TO authenticated USING (auth.uid() = user_id OR public.is_admin()) WITH CHECK (auth.uid() = user_id OR public.is_admin());
  CREATE POLICY push_notifications_service_all ON public.push_notifications FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
-- WALLETS / WALLET_DEPOSITS (own + service)
DO $$
BEGIN
  IF to_regclass('public.wallets') IS NOT NULL THEN
    ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
    CREATE POLICY wallets_select_own ON public.wallets FOR SELECT TO authenticated USING (auth.uid() = user_id);
    CREATE POLICY wallets_insert_own ON public.wallets FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
    CREATE POLICY wallets_update_own ON public.wallets FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    CREATE POLICY wallets_no_delete ON public.wallets FOR DELETE TO authenticated USING (false);
    CREATE POLICY wallets_service_all ON public.wallets FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;

  IF to_regclass('public.wallet_deposits') IS NOT NULL THEN
    ALTER TABLE public.wallet_deposits ENABLE ROW LEVEL SECURITY;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='wallet_deposits' AND column_name='user_id') THEN
      CREATE POLICY wallet_deposits_select_own ON public.wallet_deposits FOR SELECT TO authenticated USING (auth.uid() = user_id);
      CREATE POLICY wallet_deposits_insert_own ON public.wallet_deposits FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
      CREATE POLICY wallet_deposits_update_own ON public.wallet_deposits FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='wallet_deposits' AND column_name='wallet_id') THEN
      CREATE POLICY wallet_deposits_select_own ON public.wallet_deposits FOR SELECT TO authenticated USING (wallet_id IN (SELECT id FROM public.wallets WHERE user_id = auth.uid()));
      CREATE POLICY wallet_deposits_insert_own ON public.wallet_deposits FOR INSERT TO authenticated WITH CHECK (wallet_id IN (SELECT id FROM public.wallets WHERE user_id = auth.uid()));
      CREATE POLICY wallet_deposits_update_own ON public.wallet_deposits FOR UPDATE TO authenticated USING (wallet_id IN (SELECT id FROM public.wallets WHERE user_id = auth.uid())) WITH CHECK (wallet_id IN (SELECT id FROM public.wallets WHERE user_id = auth.uid()));
    END IF;
    CREATE POLICY wallet_deposits_service_all ON public.wallet_deposits FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
END $$;
-- PAYMENT_SPLITS / WEBHOOK_EVENTS
DO $$
BEGIN
  IF to_regclass('public.payment_splits') IS NOT NULL THEN
    ALTER TABLE public.payment_splits ENABLE ROW LEVEL SECURITY;
    CREATE POLICY payment_splits_select_participants ON public.payment_splits
      FOR SELECT TO authenticated
      USING (
        order_id IN (
          SELECT o.id FROM public.orders o
          LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
          WHERE
            (to_jsonb(o) ? 'client_id' AND (to_jsonb(o)->>'client_id')::uuid = auth.uid())
            OR (to_jsonb(o) ? 'courier_id' AND (to_jsonb(o)->>'courier_id')::uuid = auth.uid())
            OR (r.owner_id = auth.uid())
        )
      );
    CREATE POLICY payment_splits_service_all ON public.payment_splits FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;

  IF to_regclass('public.webhook_events') IS NOT NULL THEN
    ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
    CREATE POLICY webhook_events_select_service ON public.webhook_events FOR SELECT TO service_role USING (true);
    CREATE POLICY webhook_events_insert_authenticated ON public.webhook_events FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
  END IF;
END $$;
-- MESSAGES / CHATS / CHAT_MEMBERS / CHAT_MESSAGES (authenticated only)
DO $$
BEGIN
  IF to_regclass('public.messages') IS NOT NULL THEN
    ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
    CREATE POLICY messages_participants_read ON public.messages
      FOR SELECT TO authenticated
      USING (
        (
          to_jsonb(messages) ? 'sender_id'
          AND (to_jsonb(messages)->>'sender_id')::uuid = auth.uid()
        )
        OR (
          to_jsonb(messages) ? 'order_id'
          AND EXISTS (
            SELECT 1
            FROM public.orders o
            LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
            WHERE o.id = (to_jsonb(messages)->>'order_id')::uuid
              AND (
                (to_jsonb(o) ? 'client_id' AND (to_jsonb(o)->>'client_id')::uuid = auth.uid())
                OR (to_jsonb(o) ? 'courier_id' AND (to_jsonb(o)->>'courier_id')::uuid = auth.uid())
                OR (r.owner_id = auth.uid())
              )
          )
        )
        OR public.is_admin()
      );
    CREATE POLICY messages_participants_insert ON public.messages
      FOR INSERT TO authenticated
      WITH CHECK (
        to_jsonb(messages) ? 'sender_id'
        AND (to_jsonb(messages)->>'sender_id')::uuid = auth.uid()
      );
    CREATE POLICY messages_service_all ON public.messages FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;

  IF to_regclass('public.chats') IS NOT NULL THEN
    ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
    CREATE POLICY chats_participants_read ON public.chats
      FOR SELECT TO authenticated
      USING (
        public.is_admin()
        OR (to_jsonb(chats) ? 'client_id' AND (to_jsonb(chats)->>'client_id')::uuid = auth.uid())
        OR (to_jsonb(chats) ? 'courier_id' AND (to_jsonb(chats)->>'courier_id')::uuid = auth.uid())
        OR (to_jsonb(chats) ? 'restaurant_id' AND (to_jsonb(chats)->>'restaurant_id')::uuid = auth.uid())
        OR (to_jsonb(chats) ? 'user_id' AND (to_jsonb(chats)->>'user_id')::uuid = auth.uid())
      );
    CREATE POLICY chats_service_all ON public.chats FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;

  IF to_regclass('public.chat_members') IS NOT NULL THEN
    ALTER TABLE public.chat_members ENABLE ROW LEVEL SECURITY;
    CREATE POLICY chat_members_select_own ON public.chat_members
      FOR SELECT TO authenticated
      USING (auth.uid() = user_id OR public.is_admin());
    CREATE POLICY chat_members_manage_own ON public.chat_members
      FOR ALL TO authenticated
      USING (auth.uid() = user_id OR public.is_admin())
      WITH CHECK (auth.uid() = user_id OR public.is_admin());
    CREATE POLICY chat_members_service_all ON public.chat_members FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;

  IF to_regclass('public.chat_messages') IS NOT NULL THEN
    ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
    CREATE POLICY chat_messages_select_participants ON public.chat_messages
      FOR SELECT TO authenticated
      USING (
        (to_jsonb(chat_messages) ? 'sender_id' AND (to_jsonb(chat_messages)->>'sender_id')::uuid = auth.uid())
        OR (
          to_regclass('public.chat_members') IS NOT NULL
          AND (to_jsonb(chat_messages) ? 'chat_id'
            AND EXISTS (
              SELECT 1 FROM public.chat_members cm
              WHERE cm.chat_id = (to_jsonb(chat_messages)->>'chat_id')::uuid
                AND cm.user_id = auth.uid()
            )
          )
        )
        OR public.is_admin()
      );
    CREATE POLICY chat_messages_insert_own ON public.chat_messages
      FOR INSERT TO authenticated
      WITH CHECK (
        (to_jsonb(chat_messages) ? 'sender_id' AND (to_jsonb(chat_messages)->>'sender_id')::uuid = auth.uid())
      );
    CREATE POLICY chat_messages_service_all ON public.chat_messages FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
END $$;
-- COURIER_LOCATIONS (own write/read; optional participant read)
DO $$
BEGIN
  IF to_regclass('public.courier_locations') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.courier_locations ENABLE ROW LEVEL SECURITY;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='courier_locations' AND column_name='courier_id') THEN
    CREATE POLICY courier_locations_select_own ON public.courier_locations FOR SELECT TO authenticated USING (courier_id = auth.uid());
    CREATE POLICY courier_locations_write_own ON public.courier_locations FOR ALL TO authenticated USING (courier_id = auth.uid()) WITH CHECK (courier_id = auth.uid());
  ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='courier_locations' AND column_name='user_id') THEN
    CREATE POLICY courier_locations_select_own ON public.courier_locations FOR SELECT TO authenticated USING (user_id = auth.uid());
    CREATE POLICY courier_locations_write_own ON public.courier_locations FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
  END IF;
  CREATE POLICY courier_locations_service_all ON public.courier_locations FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
-- KYC REQUESTS (own submit/view; service/admin all)
DO $$
DECLARE owner_col text;
BEGIN
  IF to_regclass('public.kyc_requests') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.kyc_requests ENABLE ROW LEVEL SECURITY;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='kyc_requests' AND column_name='user_id') THEN
    owner_col := 'user_id';
  ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='kyc_requests' AND column_name='courier_id') THEN
    owner_col := 'courier_id';
  ELSE
    owner_col := NULL;
  END IF;
  IF owner_col IS NOT NULL THEN
    EXECUTE format('CREATE POLICY kyc_requests_select_own ON public.kyc_requests FOR SELECT TO authenticated USING (%I = auth.uid() OR public.is_admin())', owner_col);
    EXECUTE format('CREATE POLICY kyc_requests_insert_own ON public.kyc_requests FOR INSERT TO authenticated WITH CHECK (%I = auth.uid() OR public.is_admin())', owner_col);
  END IF;
  CREATE POLICY kyc_requests_service_all ON public.kyc_requests FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
-- USER-SPECIFIC GAMIFICATION (achievements, points, streaks, user_missions)
DO $$
BEGIN
  IF to_regclass('public.achievements') IS NOT NULL THEN
    ALTER TABLE public.achievements ENABLE ROW LEVEL SECURITY;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='achievements' AND column_name='user_id') THEN
      CREATE POLICY achievements_self_read ON public.achievements FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
    END IF;
    CREATE POLICY achievements_service_all ON public.achievements FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF to_regclass('public.points_transactions') IS NOT NULL THEN
    ALTER TABLE public.points_transactions ENABLE ROW LEVEL SECURITY;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='points_transactions' AND column_name='user_id') THEN
      CREATE POLICY points_transactions_self_read ON public.points_transactions FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
    END IF;
    CREATE POLICY points_transactions_service_all ON public.points_transactions FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF to_regclass('public.streaks') IS NOT NULL THEN
    ALTER TABLE public.streaks ENABLE ROW LEVEL SECURITY;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='streaks' AND column_name='user_id') THEN
      CREATE POLICY streaks_self_read ON public.streaks FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
    END IF;
    CREATE POLICY streaks_service_all ON public.streaks FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF to_regclass('public.user_missions') IS NOT NULL THEN
    ALTER TABLE public.user_missions ENABLE ROW LEVEL SECURITY;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_missions' AND column_name='user_id') THEN
      CREATE POLICY user_missions_self_read ON public.user_missions FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
    END IF;
    CREATE POLICY user_missions_service_all ON public.user_missions FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
END $$;
-- INTERNAL / ADMIN TABLES: service_role only
DO $$
DECLARE
  t text;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'admin_earnings','admin_wallets','alerts_config','commissions_ledger','commissions_v2',
    'courier_documents','cron_job_metrics','financial_holds','financial_logs','gamification_settings',
    'internal_secrets','menu_categories','missions','order_settled_v1','order_status_history',
    'outbox_audit_log','outbox_dispatches','outgoing_webhooks','payment_reconciliations',
    'payment_webhook_events','payouts_queue','processed_events','processed_transactions',
    'processing_metrics','realtime_outbox','realtime_outbox_dlq','restaurant_operating_hours',
    'route_cache','user_achievements','user_gamification','user_points','user_xp','xp_conversions',
    'xp_events','user_trigger_errors','admin_orders_policies_backup'
  ])
  LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_service_all', t);
      EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL TO service_role USING (true) WITH CHECK (true)', t || '_service_all', t);
    END IF;
  END LOOP;
END $$;
-- RLS enablement for courier_profiles (self/admin/service)
DO $$
BEGIN
  IF to_regclass('public.courier_profiles') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.courier_profiles ENABLE ROW LEVEL SECURITY;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='courier_profiles' AND column_name='user_id') THEN
    CREATE POLICY courier_profiles_select_own ON public.courier_profiles FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
    CREATE POLICY courier_profiles_update_own ON public.courier_profiles FOR UPDATE TO authenticated USING (auth.uid() = user_id OR public.is_admin()) WITH CHECK (auth.uid() = user_id OR public.is_admin());
    CREATE POLICY courier_profiles_insert_own ON public.courier_profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id OR public.is_admin());
  END IF;
  CREATE POLICY courier_profiles_service_all ON public.courier_profiles FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
COMMIT;
