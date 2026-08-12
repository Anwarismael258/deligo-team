BEGIN;
ALTER TABLE IF EXISTS public.payments
  ADD COLUMN IF NOT EXISTS provider TEXT DEFAULT 'internal_wallet',
  ADD COLUMN IF NOT EXISTS gateway_fee NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS settled_at TIMESTAMPTZ;
ALTER TABLE IF EXISTS public.payment_splits
  ADD COLUMN IF NOT EXISTS escrow_amount NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS gateway_fee NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS restaurant_fee_percent NUMERIC DEFAULT 0.06,
  ADD COLUMN IF NOT EXISTS courier_fee_percent NUMERIC DEFAULT 0.05,
  ADD COLUMN IF NOT EXISTS restaurant_platform_fee NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS courier_platform_fee NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS restaurant_confirmed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS settled_at TIMESTAMPTZ;
CREATE TABLE IF NOT EXISTS public.wallet_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id UUID NULL REFERENCES public.wallets(id) ON DELETE SET NULL,
  user_id UUID NULL,
  order_id UUID NULL,
  payment_id UUID NULL,
  direction TEXT NOT NULL CHECK (direction IN ('debit', 'credit')),
  entry_type TEXT NOT NULL,
  amount NUMERIC NOT NULL DEFAULT 0,
  balance_before NUMERIC NULL,
  balance_after NUMERIC NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wallet_ledger_wallet_id ON public.wallet_ledger(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_ledger_user_id ON public.wallet_ledger(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_ledger_order_id ON public.wallet_ledger(order_id);
CREATE INDEX IF NOT EXISTS idx_wallet_ledger_created_at ON public.wallet_ledger(created_at DESC);
ALTER TABLE public.wallet_ledger ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'wallet_ledger' AND policyname = 'wallet_ledger_select_own'
  ) THEN
    CREATE POLICY wallet_ledger_select_own
    ON public.wallet_ledger
    FOR SELECT
    TO authenticated
    USING (
      user_id = auth.uid()
      OR wallet_id IN (SELECT id FROM public.wallets WHERE user_id = auth.uid())
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'wallet_ledger' AND policyname = 'wallet_ledger_service_all'
  ) THEN
    CREATE POLICY wallet_ledger_service_all
    ON public.wallet_ledger
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);
  END IF;
END $$;
CREATE OR REPLACE FUNCTION public.process_wallet_order_payment(
  p_order_id UUID,
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_wallet RECORD;
  v_payment RECORD;
  v_total NUMERIC;
  v_delivery NUMERIC;
  v_food NUMERIC;
  v_wallet_before NUMERIC;
  v_wallet_after NUMERIC;
  v_payment_id UUID;
  v_platform_food_fee NUMERIC;
  v_platform_delivery_fee NUMERIC;
  v_restaurant_amount NUMERIC;
  v_courier_amount NUMERIC;
BEGIN
  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND COALESCE(client_id, customer_id) = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  SELECT *
  INTO v_wallet
  FROM public.wallets
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'wallet_not_found';
  END IF;

  SELECT *
  INTO v_payment
  FROM public.payments
  WHERE order_id = p_order_id
  ORDER BY created_at DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF FOUND AND LOWER(COALESCE(v_payment.status, '')) = 'completed' THEN
    RETURN jsonb_build_object(
      'success', true,
      'status', 'already_paid',
      'payment_id', v_payment.id,
      'payment_ref', COALESCE(v_payment.payment_ref, v_payment.transaction_id, ('WALLET-' || LEFT(p_order_id::text, 8)))
    );
  END IF;

  v_total := COALESCE(v_order.total_amount, v_order.total, 0);
  v_delivery := COALESCE(v_order.delivery_fee, 0);
  v_food := GREATEST(v_total - v_delivery, 0);

  IF COALESCE(v_wallet.balance, 0) < v_total THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  v_wallet_before := COALESCE(v_wallet.balance, 0);
  v_wallet_after := ROUND((v_wallet_before - v_total)::numeric, 2);

  UPDATE public.wallets
  SET balance = v_wallet_after,
      updated_at = NOW()
  WHERE id = v_wallet.id;

  INSERT INTO public.wallet_ledger (
    wallet_id, user_id, order_id, payment_id, direction, entry_type,
    amount, balance_before, balance_after, metadata
  ) VALUES (
    v_wallet.id,
    p_user_id,
    p_order_id,
    NULL,
    'debit',
    'order_payment_escrow',
    v_total,
    v_wallet_before,
    v_wallet_after,
    jsonb_build_object('source', 'wallet_internal', 'stage', 'escrow_reserved')
  );

  INSERT INTO public.wallet_ledger (
    wallet_id, user_id, order_id, payment_id, direction, entry_type,
    amount, balance_before, balance_after, metadata
  ) VALUES (
    NULL,
    NULL,
    p_order_id,
    NULL,
    'credit',
    'escrow_reserved',
    v_total,
    NULL,
    NULL,
    jsonb_build_object('source', 'wallet_internal', 'stage', 'escrow_reserved')
  );

  v_platform_food_fee := ROUND((v_food * 0.06)::numeric, 2);
  v_platform_delivery_fee := ROUND((v_delivery * 0.05)::numeric, 2);
  v_restaurant_amount := ROUND((v_food - v_platform_food_fee)::numeric, 2);
  v_courier_amount := ROUND((v_delivery - v_platform_delivery_fee)::numeric, 2);

  IF NOT FOUND OR v_payment.id IS NULL THEN
    INSERT INTO public.payments (
      id, order_id, amount, provider, payment_ref, payment_method, status,
      transaction_id, gateway_fee, created_at, updated_at
    ) VALUES (
      gen_random_uuid(),
      p_order_id,
      v_total,
      'internal_wallet',
      'WALLET-' || UPPER(SUBSTRING(p_order_id::text FROM 1 FOR 8)),
      'wallet',
      'completed',
      'WALLET-' || UPPER(SUBSTRING(p_order_id::text FROM 1 FOR 8)),
      0,
      NOW(),
      NOW()
    )
    RETURNING id INTO v_payment_id;
  ELSE
    UPDATE public.payments
    SET amount = v_total,
        provider = 'internal_wallet',
        payment_method = 'wallet',
        status = 'completed',
        gateway_fee = 0,
        updated_at = NOW()
    WHERE id = v_payment.id
    RETURNING id INTO v_payment_id;
  END IF;

  INSERT INTO public.payment_splits (
    id, order_id, total_amount, platform_fee, restaurant_amount, courier_amount,
    escrow_amount, gateway_fee, restaurant_fee_percent, courier_fee_percent,
    restaurant_platform_fee, courier_platform_fee, status, created_at
  )
  VALUES (
    gen_random_uuid(),
    p_order_id,
    v_total,
    v_platform_food_fee + v_platform_delivery_fee,
    v_restaurant_amount,
    v_courier_amount,
    v_total,
    0,
    0.06,
    0.05,
    v_platform_food_fee,
    v_platform_delivery_fee,
    'escrowed',
    NOW()
  )
  ON CONFLICT (order_id) DO UPDATE SET
    total_amount = EXCLUDED.total_amount,
    platform_fee = EXCLUDED.platform_fee,
    restaurant_amount = EXCLUDED.restaurant_amount,
    courier_amount = EXCLUDED.courier_amount,
    escrow_amount = EXCLUDED.escrow_amount,
    gateway_fee = EXCLUDED.gateway_fee,
    restaurant_fee_percent = EXCLUDED.restaurant_fee_percent,
    courier_fee_percent = EXCLUDED.courier_fee_percent,
    restaurant_platform_fee = EXCLUDED.restaurant_platform_fee,
    courier_platform_fee = EXCLUDED.courier_platform_fee,
    status = 'escrowed';

  UPDATE public.orders
  SET status = 'paid',
      payment_status = 'completed',
      updated_at = NOW()
  WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'status', 'completed',
    'payment_id', v_payment_id,
    'payment_ref', 'WALLET-' || UPPER(SUBSTRING(p_order_id::text FROM 1 FOR 8)),
    'wallet_balance', v_wallet_after,
    'escrow_amount', v_total
  );
END;
$$;
REVOKE ALL ON FUNCTION public.process_wallet_order_payment(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_wallet_order_payment(UUID, UUID) TO service_role;
CREATE OR REPLACE FUNCTION public.sync_payment_split_on_restaurant_confirmation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'accepted' AND COALESCE(OLD.status, '') <> 'accepted' THEN
    UPDATE public.payment_splits
    SET status = CASE WHEN status = 'escrowed' THEN 'restaurant_confirmed' ELSE status END,
        restaurant_confirmed_at = COALESCE(restaurant_confirmed_at, NOW())
    WHERE order_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_payment_split_on_restaurant_confirmation ON public.orders;
CREATE TRIGGER trg_sync_payment_split_on_restaurant_confirmation
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.sync_payment_split_on_restaurant_confirmation();
COMMIT;
