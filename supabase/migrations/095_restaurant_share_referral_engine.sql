BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS public.restaurant_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  referrer_user_id UUID NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  share_token TEXT NOT NULL UNIQUE,
  referral_code TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'restaurant_page',
  channel TEXT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_restaurant_shares_restaurant_created_at
  ON public.restaurant_shares(restaurant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_restaurant_shares_referrer_created_at
  ON public.restaurant_shares(referrer_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_restaurant_shares_referral_code
  ON public.restaurant_shares(referral_code);
ALTER TABLE public.restaurant_shares ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'restaurant_shares_select_public'
      AND polrelid = 'public.restaurant_shares'::regclass
  ) THEN
    CREATE POLICY restaurant_shares_select_public
      ON public.restaurant_shares
      FOR SELECT
      TO anon, authenticated
      USING (status = 'active');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'restaurant_shares_insert_own'
      AND polrelid = 'public.restaurant_shares'::regclass
  ) THEN
    CREATE POLICY restaurant_shares_insert_own
      ON public.restaurant_shares
      FOR INSERT
      TO authenticated
      WITH CHECK (
        referrer_user_id = auth.uid()
        OR referrer_user_id IS NULL
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'restaurant_shares_update_owner'
      AND polrelid = 'public.restaurant_shares'::regclass
  ) THEN
    CREATE POLICY restaurant_shares_update_owner
      ON public.restaurant_shares
      FOR UPDATE
      TO authenticated
      USING (referrer_user_id = auth.uid())
      WITH CHECK (referrer_user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'restaurant_shares_service_all'
      AND polrelid = 'public.restaurant_shares'::regclass
  ) THEN
    CREATE POLICY restaurant_shares_service_all
      ON public.restaurant_shares
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.restaurant_share_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  share_id UUID NOT NULL REFERENCES public.restaurant_shares(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  actor_user_id UUID NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  session_token TEXT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_restaurant_share_events_share_created_at
  ON public.restaurant_share_events(share_id, created_at DESC);
ALTER TABLE public.restaurant_share_events ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'restaurant_share_events_select_related'
      AND polrelid = 'public.restaurant_share_events'::regclass
  ) THEN
    CREATE POLICY restaurant_share_events_select_related
      ON public.restaurant_share_events
      FOR SELECT
      TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.restaurant_shares s
          WHERE s.id = share_id
            AND (
              s.referrer_user_id = auth.uid()
              OR EXISTS (
                SELECT 1
                FROM public.restaurants r
                WHERE r.id = s.restaurant_id
                  AND r.owner_id = auth.uid()
              )
            )
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'restaurant_share_events_insert_authenticated'
      AND polrelid = 'public.restaurant_share_events'::regclass
  ) THEN
    CREATE POLICY restaurant_share_events_insert_authenticated
      ON public.restaurant_share_events
      FOR INSERT
      TO authenticated
      WITH CHECK (
        actor_user_id = auth.uid()
        OR actor_user_id IS NULL
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'restaurant_share_events_service_all'
      AND polrelid = 'public.restaurant_share_events'::regclass
  ) THEN
    CREATE POLICY restaurant_share_events_service_all
      ON public.restaurant_share_events
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.restaurant_referral_rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  share_id UUID NOT NULL REFERENCES public.restaurant_shares(id) ON DELETE CASCADE,
  order_id UUID NULL REFERENCES public.orders(id) ON DELETE SET NULL,
  referrer_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  referee_user_id UUID NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
  referrer_reward_type TEXT NOT NULL DEFAULT 'wallet_bonus_percent',
  referrer_reward_value NUMERIC(10,2) NOT NULL DEFAULT 3,
  referrer_reward_cap NUMERIC(10,2) NOT NULL DEFAULT 50,
  referee_reward_type TEXT NOT NULL DEFAULT 'first_order_discount_percent',
  referee_reward_value NUMERIC(10,2) NOT NULL DEFAULT 10,
  referee_reward_cap NUMERIC(10,2) NOT NULL DEFAULT 100,
  minimum_order_amount NUMERIC(10,2) NOT NULL DEFAULT 300,
  status TEXT NOT NULL DEFAULT 'pending',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_restaurant_referral_rewards_referrer_created_at
  ON public.restaurant_referral_rewards(referrer_user_id, created_at DESC);
ALTER TABLE public.restaurant_referral_rewards ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'restaurant_referral_rewards_select_related'
      AND polrelid = 'public.restaurant_referral_rewards'::regclass
  ) THEN
    CREATE POLICY restaurant_referral_rewards_select_related
      ON public.restaurant_referral_rewards
      FOR SELECT
      TO authenticated
      USING (
        referrer_user_id = auth.uid()
        OR referee_user_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.restaurant_shares s
          JOIN public.restaurants r ON r.id = s.restaurant_id
          WHERE s.id = share_id
            AND r.owner_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'restaurant_referral_rewards_service_all'
      AND polrelid = 'public.restaurant_referral_rewards'::regclass
  ) THEN
    CREATE POLICY restaurant_referral_rewards_service_all
      ON public.restaurant_referral_rewards
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
CREATE OR REPLACE VIEW public.restaurant_share_stats AS
SELECT
  s.restaurant_id,
  COUNT(*) AS total_shares,
  COUNT(e.*) FILTER (WHERE e.event_type = 'share_channel_opened') AS channel_opens,
  COUNT(e.*) FILTER (WHERE e.event_type = 'magic_link_copied') AS magic_link_copies,
  COUNT(rr.*) FILTER (WHERE rr.status IN ('pending', 'granted')) AS rewards_generated,
  MAX(s.created_at) AS last_share_at
FROM public.restaurant_shares s
LEFT JOIN public.restaurant_share_events e ON e.share_id = s.id
LEFT JOIN public.restaurant_referral_rewards rr ON rr.share_id = s.id
GROUP BY s.restaurant_id;
CREATE OR REPLACE FUNCTION public.settle_restaurant_referral_reward()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reward RECORD;
  v_wallet RECORD;
  v_bonus_amount NUMERIC(10,2);
  v_reference_key TEXT;
BEGIN
  IF COALESCE(NEW.status, '') <> 'completed'
     OR COALESCE(OLD.status, '') = 'completed' THEN
    RETURN NEW;
  END IF;

  FOR v_reward IN
    SELECT *
    FROM public.restaurant_referral_rewards
    WHERE order_id = NEW.id
      AND status = 'pending'
  LOOP
    IF COALESCE(v_reward.referrer_user_id, v_reward.referee_user_id) IS NULL THEN
      CONTINUE;
    END IF;

    v_bonus_amount := LEAST(
      ROUND((COALESCE(NEW.total_amount, NEW.total, 0) * COALESCE(v_reward.referrer_reward_value, 0) / 100.0)::numeric, 2),
      COALESCE(v_reward.referrer_reward_cap, 50)
    );

    IF v_bonus_amount <= 0 THEN
      UPDATE public.restaurant_referral_rewards
      SET status = 'failed',
          updated_at = NOW(),
          metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
            'failure_reason', 'invalid_bonus_amount',
            'settled_at', NOW()
          )
      WHERE id = v_reward.id;
      CONTINUE;
    END IF;

    SELECT id, balance
    INTO v_wallet
    FROM public.wallets
    WHERE user_id = v_reward.referrer_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
      INSERT INTO public.wallets (user_id, balance, currency, is_active, created_at, updated_at)
      VALUES (v_reward.referrer_user_id, 0, 'MZN', TRUE, NOW(), NOW())
      RETURNING id, balance INTO v_wallet;
    END IF;

    v_reference_key := 'referral_reward_' || v_reward.id::text;

    PERFORM public.apply_wallet_ledger_entry(
      p_wallet_id := v_wallet.id,
      p_user_id := v_reward.referrer_user_id,
      p_order_id := NEW.id,
      p_payment_id := NULL,
      p_direction := 'credit',
      p_entry_type := 'referral_share_reward',
      p_amount := v_bonus_amount,
      p_reference_key := v_reference_key,
      p_metadata := jsonb_build_object(
        'share_id', v_reward.share_id,
        'reward_id', v_reward.id,
        'reward_percent', v_reward.referrer_reward_value,
        'reward_cap', v_reward.referrer_reward_cap,
        'restaurant_id', (SELECT restaurant_id FROM public.restaurant_shares WHERE id = v_reward.share_id),
        'source', 'restaurant_referral'
      ),
      p_status := 'confirmed',
      p_allow_negative := FALSE
    );

    UPDATE public.restaurant_referral_rewards
    SET status = 'granted',
        updated_at = NOW(),
        metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
          'granted_amount', v_bonus_amount,
          'granted_at', NOW(),
          'wallet_id', v_wallet.id,
          'ledger_reference_key', v_reference_key
        )
    WHERE id = v_reward.id;
  END LOOP;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_settle_restaurant_referral_reward ON public.orders;
CREATE TRIGGER trg_settle_restaurant_referral_reward
AFTER UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.settle_restaurant_referral_reward();
COMMIT;
