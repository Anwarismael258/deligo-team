BEGIN;
ALTER TABLE IF EXISTS public.orders
  ADD COLUMN IF NOT EXISTS funds_status TEXT NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS financial_outcome TEXT,
  ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'MZN',
  ADD COLUMN IF NOT EXISTS order_completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS settlement_processed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;
ALTER TABLE IF EXISTS public.orders
  DROP CONSTRAINT IF EXISTS orders_funds_status_check;
ALTER TABLE IF EXISTS public.orders
  ADD CONSTRAINT orders_funds_status_check
  CHECK (
    funds_status IN (
      'none',
      'held_in_escrow',
      'released',
      'refunded',
      'partially_refunded',
      'manual_review'
    )
  );
ALTER TABLE IF EXISTS public.orders
  DROP CONSTRAINT IF EXISTS orders_currency_check;
ALTER TABLE IF EXISTS public.orders
  ADD CONSTRAINT orders_currency_check
  CHECK (currency ~ '^[A-Z]{3}$');
ALTER TABLE IF EXISTS public.payments
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT,
  ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'MZN',
  ADD COLUMN IF NOT EXISTS authorized_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS failed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS refunded_at TIMESTAMPTZ;
ALTER TABLE IF EXISTS public.payments
  DROP CONSTRAINT IF EXISTS payments_currency_check;
ALTER TABLE IF EXISTS public.payments
  ADD CONSTRAINT payments_currency_check
  CHECK (currency ~ '^[A-Z]{3}$');
CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_idempotency_key_unique
  ON public.payments (idempotency_key)
  WHERE idempotency_key IS NOT NULL;
ALTER TABLE IF EXISTS public.wallet_ledger
  ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'MZN',
  ADD COLUMN IF NOT EXISTS entry_group_id UUID,
  ADD COLUMN IF NOT EXISTS immutable BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE IF EXISTS public.wallet_ledger
  DROP CONSTRAINT IF EXISTS wallet_ledger_currency_check;
ALTER TABLE IF EXISTS public.wallet_ledger
  ADD CONSTRAINT wallet_ledger_currency_check
  CHECK (currency ~ '^[A-Z]{3}$');
CREATE TABLE IF NOT EXISTS public.idempotency_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scope TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  request_hash TEXT,
  status TEXT NOT NULL DEFAULT 'started',
  resource_type TEXT,
  resource_id UUID,
  response_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT idempotency_keys_status_check
    CHECK (status IN ('started', 'completed', 'failed'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_idempotency_keys_scope_key_unique
  ON public.idempotency_keys(scope, idempotency_key);
CREATE TABLE IF NOT EXISTS public.financial_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_code TEXT NOT NULL,
  account_name TEXT NOT NULL,
  account_type TEXT NOT NULL,
  owner_type TEXT NOT NULL,
  owner_id UUID,
  currency TEXT NOT NULL DEFAULT 'MZN',
  is_system_account BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT financial_accounts_type_check
    CHECK (account_type IN ('asset', 'liability', 'revenue', 'expense', 'clearing')),
  CONSTRAINT financial_accounts_owner_type_check
    CHECK (
      owner_type IN (
        'system',
        'wallet',
        'user',
        'restaurant',
        'courier',
        'platform'
      )
    ),
  CONSTRAINT financial_accounts_currency_check
    CHECK (currency ~ '^[A-Z]{3}$')
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_financial_accounts_code_unique
  ON public.financial_accounts(account_code);
CREATE TABLE IF NOT EXISTS public.financial_ledger_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_group_id UUID NOT NULL,
  idempotency_key TEXT NOT NULL,
  order_id UUID,
  payment_id UUID,
  payout_id UUID,
  account_id UUID NOT NULL REFERENCES public.financial_accounts(id),
  direction TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  currency TEXT NOT NULL DEFAULT 'MZN',
  entry_type TEXT NOT NULL,
  reference_type TEXT,
  reference_id UUID,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT financial_ledger_entries_direction_check
    CHECK (direction IN ('debit', 'credit')),
  CONSTRAINT financial_ledger_entries_amount_check
    CHECK (amount >= 0),
  CONSTRAINT financial_ledger_entries_currency_check
    CHECK (currency ~ '^[A-Z]{3}$')
);
CREATE INDEX IF NOT EXISTS idx_financial_ledger_entries_group_id
  ON public.financial_ledger_entries(entry_group_id);
CREATE INDEX IF NOT EXISTS idx_financial_ledger_entries_order_id
  ON public.financial_ledger_entries(order_id);
CREATE INDEX IF NOT EXISTS idx_financial_ledger_entries_payment_id
  ON public.financial_ledger_entries(payment_id);
CREATE INDEX IF NOT EXISTS idx_financial_ledger_entries_created_at
  ON public.financial_ledger_entries(created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_financial_ledger_entries_idempotency_account_direction_unique
  ON public.financial_ledger_entries(idempotency_key, account_id, direction, amount, entry_type);
CREATE TABLE IF NOT EXISTS public.order_financial_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL UNIQUE,
  currency TEXT NOT NULL DEFAULT 'MZN',
  subtotal NUMERIC NOT NULL DEFAULT 0,
  delivery_fee NUMERIC NOT NULL DEFAULT 0,
  total_amount NUMERIC NOT NULL DEFAULT 0,
  platform_commission_amount NUMERIC NOT NULL DEFAULT 0,
  platform_delivery_fee_amount NUMERIC NOT NULL DEFAULT 0,
  restaurant_net_amount NUMERIC NOT NULL DEFAULT 0,
  courier_net_amount NUMERIC NOT NULL DEFAULT 0,
  gateway_fee_amount NUMERIC NOT NULL DEFAULT 0,
  escrow_amount NUMERIC NOT NULL DEFAULT 0,
  snapshot_version INTEGER NOT NULL DEFAULT 1,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT order_financial_snapshots_currency_check
    CHECK (currency ~ '^[A-Z]{3}$')
);
CREATE TABLE IF NOT EXISTS public.payouts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid()
);
ALTER TABLE IF EXISTS public.payouts
  ADD COLUMN IF NOT EXISTS order_id UUID,
  ADD COLUMN IF NOT EXISTS payout_type TEXT,
  ADD COLUMN IF NOT EXISTS entity_type TEXT,
  ADD COLUMN IF NOT EXISTS entity_id UUID,
  ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'MZN',
  ADD COLUMN IF NOT EXISTS amount NUMERIC NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT,
  ADD COLUMN IF NOT EXISTS external_reference TEXT,
  ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS processed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE IF EXISTS public.payouts
  DROP CONSTRAINT IF EXISTS payouts_status_check;
ALTER TABLE IF EXISTS public.payouts
  ADD CONSTRAINT payouts_status_check
  CHECK (status IN ('pending', 'processing', 'paid', 'failed', 'cancelled'));
ALTER TABLE IF EXISTS public.payouts
  DROP CONSTRAINT IF EXISTS payouts_entity_type_check;
ALTER TABLE IF EXISTS public.payouts
  ADD CONSTRAINT payouts_entity_type_check
  CHECK (entity_type IS NULL OR entity_type IN ('restaurant', 'courier', 'platform'));
ALTER TABLE IF EXISTS public.payouts
  DROP CONSTRAINT IF EXISTS payouts_amount_check;
ALTER TABLE IF EXISTS public.payouts
  ADD CONSTRAINT payouts_amount_check
  CHECK (amount >= 0);
ALTER TABLE IF EXISTS public.payouts
  DROP CONSTRAINT IF EXISTS payouts_currency_check;
ALTER TABLE IF EXISTS public.payouts
  ADD CONSTRAINT payouts_currency_check
  CHECK (currency ~ '^[A-Z]{3}$');
CREATE UNIQUE INDEX IF NOT EXISTS idx_payouts_idempotency_key_unique
  ON public.payouts(idempotency_key);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payouts_order_entity_type_entity_id_payout_type_unique
  ON public.payouts(order_id, entity_type, COALESCE(entity_id, '00000000-0000-0000-0000-000000000000'::uuid), payout_type);
CREATE OR REPLACE FUNCTION public.validate_order_transition(
  p_from_status TEXT,
  p_to_status TEXT,
  p_delivery_type TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_from TEXT := LOWER(COALESCE(p_from_status, ''));
  v_to TEXT := LOWER(COALESCE(p_to_status, ''));
  v_delivery_type TEXT := LOWER(COALESCE(p_delivery_type, 'delivery'));
BEGIN
  IF v_from = '' OR v_to = '' THEN
    RETURN FALSE;
  END IF;

  IF v_from = v_to THEN
    RETURN TRUE;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM (
      VALUES
        ('pending', 'payment_authorized', NULL),
        ('pending', 'paid', NULL),
        ('pending', 'payment_failed', NULL),
        ('pending', 'cancelled', NULL),
        ('paid', 'accepted', NULL),
        ('paid', 'expired', NULL),
        ('payment_authorized', 'accepted', NULL),
        ('payment_authorized', 'expired', NULL),
        ('payment_authorized', 'cancelled', NULL),
        ('accepted', 'preparing', NULL),
        ('preparing', 'ready', NULL),
        ('ready', 'awaiting_pickup_confirmation', 'pickup'),
        ('awaiting_pickup_confirmation', 'completed', 'pickup'),
        ('ready', 'picked_up', 'delivery'),
        ('picked_up', 'in_delivery', 'delivery'),
        ('in_delivery', 'arrived', 'delivery'),
        ('arrived', 'delivered', 'delivery'),
        ('delivered', 'completed', 'delivery'),
        ('ready', 'completed', NULL),
        ('cancelled', 'refunded', NULL),
        ('expired', 'refunded', NULL)
    ) AS allowed(from_status, to_status, delivery_type)
    WHERE allowed.from_status = v_from
      AND allowed.to_status = v_to
      AND (allowed.delivery_type IS NULL OR allowed.delivery_type = v_delivery_type)
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_idempotency_keys_touch_updated_at ON public.idempotency_keys;
CREATE TRIGGER trg_idempotency_keys_touch_updated_at
BEFORE UPDATE ON public.idempotency_keys
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();
DROP TRIGGER IF EXISTS trg_financial_accounts_touch_updated_at ON public.financial_accounts;
CREATE TRIGGER trg_financial_accounts_touch_updated_at
BEFORE UPDATE ON public.financial_accounts
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();
DROP TRIGGER IF EXISTS trg_payouts_touch_updated_at ON public.payouts;
CREATE TRIGGER trg_payouts_touch_updated_at
BEFORE UPDATE ON public.payouts
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();
ALTER TABLE public.idempotency_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_financial_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payouts ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'idempotency_keys'
      AND policyname = 'idempotency_keys_service_all'
  ) THEN
    CREATE POLICY idempotency_keys_service_all
      ON public.idempotency_keys
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'financial_accounts'
      AND policyname = 'financial_accounts_service_all'
  ) THEN
    CREATE POLICY financial_accounts_service_all
      ON public.financial_accounts
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'financial_ledger_entries'
      AND policyname = 'financial_ledger_entries_service_all'
  ) THEN
    CREATE POLICY financial_ledger_entries_service_all
      ON public.financial_ledger_entries
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'order_financial_snapshots'
      AND policyname = 'order_financial_snapshots_service_all'
  ) THEN
    CREATE POLICY order_financial_snapshots_service_all
      ON public.order_financial_snapshots
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'payouts'
      AND policyname = 'payouts_service_all'
  ) THEN
    CREATE POLICY payouts_service_all
      ON public.payouts
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
INSERT INTO public.financial_accounts (
  account_code,
  account_name,
  account_type,
  owner_type,
  owner_id,
  currency,
  is_system_account,
  metadata
)
VALUES
  ('SYS_ESCROW_MZN', 'System Escrow MZN', 'liability', 'system', NULL, 'MZN', TRUE, '{"purpose":"escrow"}'::jsonb),
  ('SYS_PLATFORM_REVENUE_MZN', 'Platform Revenue MZN', 'revenue', 'platform', NULL, 'MZN', TRUE, '{"purpose":"platform_revenue"}'::jsonb)
ON CONFLICT (account_code) DO NOTHING;
COMMENT ON TABLE public.idempotency_keys IS
  'Registry for global idempotency across payments, escrow, refunds, ledger posting, and payouts.';
COMMENT ON TABLE public.financial_ledger_entries IS
  'Append-only double-entry financial ledger. Operational states should not be treated as the financial source of truth.';
COMMENT ON FUNCTION public.validate_order_transition(TEXT, TEXT, TEXT) IS
  'Returns whether an order status transition is allowed for the given delivery type.';
COMMIT;
