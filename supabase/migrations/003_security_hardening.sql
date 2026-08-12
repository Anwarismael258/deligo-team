-- 003_security_hardening.sql
-- Security and consistency hardening for production.

BEGIN;
-- Keep FK/nullability behavior consistent only when columns exist.
DO $$
BEGIN
  IF to_regclass('public.orders') IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'client_id'
    ) THEN
      ALTER TABLE public.orders ALTER COLUMN client_id DROP NOT NULL;
    END IF;

    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'restaurant_id'
    ) THEN
      ALTER TABLE public.orders ALTER COLUMN restaurant_id DROP NOT NULL;
    END IF;
  END IF;

  IF to_regclass('public.deliveries') IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'deliveries' AND column_name = 'courier_id'
    ) THEN
      ALTER TABLE public.deliveries ALTER COLUMN courier_id DROP NOT NULL;
    END IF;
  END IF;
END $$;
-- Harden wallets policies.
DO $$
BEGIN
  IF to_regclass('public.wallets') IS NULL THEN
    RETURN;
  END IF;

  ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "Users can view own wallet" ON public.wallets;
  DROP POLICY IF EXISTS "Service can manage wallets" ON public.wallets;
  DROP POLICY IF EXISTS wallets_select_own ON public.wallets;
  DROP POLICY IF EXISTS wallets_insert_own ON public.wallets;
  DROP POLICY IF EXISTS wallets_update_own ON public.wallets;
  DROP POLICY IF EXISTS wallets_service_all ON public.wallets;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'wallets' AND column_name = 'user_id'
  ) THEN
    CREATE POLICY wallets_select_own
      ON public.wallets
      FOR SELECT
      USING (auth.uid() = user_id);

    CREATE POLICY wallets_insert_own
      ON public.wallets
      FOR INSERT
      WITH CHECK (auth.uid() = user_id);

    CREATE POLICY wallets_update_own
      ON public.wallets
      FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;

  CREATE POLICY wallets_service_all
    ON public.wallets
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');
END $$;
-- Harden wallet_deposits policies (supports both user_id and wallet_id schemas).
DO $$
BEGIN
  IF to_regclass('public.wallet_deposits') IS NULL THEN
    RETURN;
  END IF;

  ALTER TABLE public.wallet_deposits ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "Users can view own deposits" ON public.wallet_deposits;
  DROP POLICY IF EXISTS "Service can manage deposits" ON public.wallet_deposits;
  DROP POLICY IF EXISTS wallet_deposits_select_own ON public.wallet_deposits;
  DROP POLICY IF EXISTS wallet_deposits_insert_own ON public.wallet_deposits;
  DROP POLICY IF EXISTS wallet_deposits_update_own ON public.wallet_deposits;
  DROP POLICY IF EXISTS wallet_deposits_service_all ON public.wallet_deposits;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'wallet_deposits' AND column_name = 'user_id'
  ) THEN
    CREATE POLICY wallet_deposits_select_own
      ON public.wallet_deposits
      FOR SELECT
      USING (auth.uid() = user_id);

    CREATE POLICY wallet_deposits_insert_own
      ON public.wallet_deposits
      FOR INSERT
      WITH CHECK (auth.uid() = user_id);

    CREATE POLICY wallet_deposits_update_own
      ON public.wallet_deposits
      FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'wallet_deposits' AND column_name = 'wallet_id'
  ) AND to_regclass('public.wallets') IS NOT NULL THEN
    CREATE POLICY wallet_deposits_select_own
      ON public.wallet_deposits
      FOR SELECT
      USING (wallet_id IN (SELECT id FROM public.wallets WHERE user_id = auth.uid()));

    CREATE POLICY wallet_deposits_insert_own
      ON public.wallet_deposits
      FOR INSERT
      WITH CHECK (wallet_id IN (SELECT id FROM public.wallets WHERE user_id = auth.uid()));

    CREATE POLICY wallet_deposits_update_own
      ON public.wallet_deposits
      FOR UPDATE
      USING (wallet_id IN (SELECT id FROM public.wallets WHERE user_id = auth.uid()))
      WITH CHECK (wallet_id IN (SELECT id FROM public.wallets WHERE user_id = auth.uid()));
  END IF;

  CREATE POLICY wallet_deposits_service_all
    ON public.wallet_deposits
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');
END $$;
-- Harden payment_splits policies when schema supports participant visibility.
DO $$
BEGIN
  IF to_regclass('public.payment_splits') IS NULL THEN
    RETURN;
  END IF;

  ALTER TABLE public.payment_splits ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "Users can view payment splits" ON public.payment_splits;
  DROP POLICY IF EXISTS "Service can manage payment splits" ON public.payment_splits;
  DROP POLICY IF EXISTS payment_splits_select_participants ON public.payment_splits;
  DROP POLICY IF EXISTS payment_splits_service_all ON public.payment_splits;

  IF to_regclass('public.orders') IS NOT NULL THEN
    CREATE POLICY payment_splits_select_participants
      ON public.payment_splits
      FOR SELECT
      USING (
        order_id IN (
          SELECT o.id
          FROM public.orders o
          LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
          WHERE (
            (to_jsonb(o) ? 'client_id' AND (to_jsonb(o)->>'client_id')::uuid = auth.uid())
            OR (to_jsonb(o) ? 'courier_id' AND (to_jsonb(o)->>'courier_id')::uuid = auth.uid())
            OR (r.owner_id = auth.uid())
          )
        )
      );
  END IF;

  CREATE POLICY payment_splits_service_all
    ON public.payment_splits
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');
END $$;
-- Harden webhook_events policies.
DO $$
BEGIN
  IF to_regclass('public.webhook_events') IS NULL THEN
    RETURN;
  END IF;

  ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "Admins can view webhook events" ON public.webhook_events;
  DROP POLICY IF EXISTS "Service can insert webhook events" ON public.webhook_events;
  DROP POLICY IF EXISTS webhook_events_select_service ON public.webhook_events;
  DROP POLICY IF EXISTS webhook_events_insert_authenticated ON public.webhook_events;

  CREATE POLICY webhook_events_select_service
    ON public.webhook_events
    FOR SELECT
    USING (auth.role() = 'service_role');

  CREATE POLICY webhook_events_insert_authenticated
    ON public.webhook_events
    FOR INSERT
    WITH CHECK (auth.role() = 'service_role' OR auth.uid() IS NOT NULL);
END $$;
-- Ensure orders table has RLS and insert policy compatible with current schema.
DO $$
BEGIN
  IF to_regclass('public.orders') IS NULL THEN
    RETURN;
  END IF;

  ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
  DROP POLICY IF EXISTS orders_insert_own ON public.orders;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'client_id'
  ) THEN
    CREATE POLICY orders_insert_own
      ON public.orders
      FOR INSERT
      WITH CHECK (auth.uid() = client_id);
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'user_id'
  ) THEN
    CREATE POLICY orders_insert_own
      ON public.orders
      FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;
COMMIT;
