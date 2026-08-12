BEGIN;
ALTER TABLE IF EXISTS public.wallet_ledger
  ADD COLUMN IF NOT EXISTS reference_key TEXT,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'confirmed';
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'wallet_ledger_status_check'
  ) THEN
    ALTER TABLE public.wallet_ledger
      ADD CONSTRAINT wallet_ledger_status_check
      CHECK (status IN ('pending', 'confirmed', 'failed', 'reversed'));
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS idx_wallet_ledger_reference_key_unique
  ON public.wallet_ledger(reference_key)
  WHERE reference_key IS NOT NULL;
CREATE OR REPLACE FUNCTION public.apply_wallet_ledger_entry(
  p_wallet_id UUID DEFAULT NULL,
  p_user_id UUID DEFAULT NULL,
  p_order_id UUID DEFAULT NULL,
  p_payment_id UUID DEFAULT NULL,
  p_direction TEXT DEFAULT 'credit',
  p_entry_type TEXT DEFAULT 'generic',
  p_amount NUMERIC DEFAULT 0,
  p_reference_key TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb,
  p_status TEXT DEFAULT 'confirmed',
  p_allow_negative BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing RECORD;
  v_wallet RECORD;
  v_before NUMERIC := NULL;
  v_after NUMERIC := NULL;
  v_delta NUMERIC;
  v_entry_id UUID;
BEGIN
  IF p_amount IS NULL OR p_amount < 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  IF p_direction NOT IN ('credit', 'debit') THEN
    RAISE EXCEPTION 'invalid_direction';
  END IF;

  IF p_status NOT IN ('pending', 'confirmed', 'failed', 'reversed') THEN
    RAISE EXCEPTION 'invalid_ledger_status';
  END IF;

  IF p_reference_key IS NOT NULL THEN
    SELECT id, wallet_id, balance_before, balance_after, status
    INTO v_existing
    FROM public.wallet_ledger
    WHERE reference_key = p_reference_key
    LIMIT 1;

    IF v_existing.id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', true,
        'duplicate', true,
        'ledger_id', v_existing.id,
        'status', v_existing.status,
        'balance_before', v_existing.balance_before,
        'balance_after', v_existing.balance_after
      );
    END IF;
  END IF;

  IF p_wallet_id IS NOT NULL THEN
    SELECT id, user_id, balance
    INTO v_wallet
    FROM public.wallets
    WHERE id = p_wallet_id
    FOR UPDATE;

    IF v_wallet.id IS NULL THEN
      RAISE EXCEPTION 'wallet_not_found';
    END IF;

    v_before := COALESCE(v_wallet.balance, 0);
    v_delta := CASE WHEN p_direction = 'credit' THEN p_amount ELSE -p_amount END;
    v_after := ROUND((v_before + v_delta)::numeric, 2);

    IF p_direction = 'debit' AND NOT p_allow_negative AND v_after < 0 THEN
      RAISE EXCEPTION 'insufficient_balance';
    END IF;

    IF p_status = 'confirmed' THEN
      UPDATE public.wallets
      SET balance = v_after,
          updated_at = NOW()
      WHERE id = p_wallet_id;
    ELSE
      v_after := v_before;
    END IF;
  END IF;

  INSERT INTO public.wallet_ledger (
    wallet_id,
    user_id,
    order_id,
    payment_id,
    direction,
    entry_type,
    amount,
    balance_before,
    balance_after,
    metadata,
    reference_key,
    status
  )
  VALUES (
    p_wallet_id,
    COALESCE(p_user_id, v_wallet.user_id),
    p_order_id,
    p_payment_id,
    p_direction,
    p_entry_type,
    p_amount,
    v_before,
    v_after,
    COALESCE(p_metadata, '{}'::jsonb),
    p_reference_key,
    p_status
  )
  RETURNING id INTO v_entry_id;

  RETURN jsonb_build_object(
    'success', true,
    'duplicate', false,
    'ledger_id', v_entry_id,
    'balance_before', v_before,
    'balance_after', v_after,
    'status', p_status
  );
END;
$$;
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
  v_payment_id UUID;
  v_platform_food_fee NUMERIC;
  v_platform_delivery_fee NUMERIC;
  v_restaurant_amount NUMERIC;
  v_courier_amount NUMERIC;
  v_result JSONB;
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

  PERFORM public.apply_wallet_ledger_entry(
    p_wallet_id := v_wallet.id,
    p_user_id := p_user_id,
    p_order_id := p_order_id,
    p_direction := 'debit',
    p_entry_type := 'order_payment_escrow',
    p_amount := v_total,
    p_reference_key := 'order-payment-escrow-' || p_order_id::text,
    p_metadata := jsonb_build_object('source', 'wallet_internal', 'stage', 'escrow_reserved'),
    p_status := 'confirmed'
  );

  PERFORM public.apply_wallet_ledger_entry(
    p_wallet_id := NULL,
    p_user_id := NULL,
    p_order_id := p_order_id,
    p_direction := 'credit',
    p_entry_type := 'escrow_reserved',
    p_amount := v_total,
    p_reference_key := 'escrow-reserved-' || p_order_id::text,
    p_metadata := jsonb_build_object('source', 'wallet_internal', 'stage', 'escrow_reserved'),
    p_status := 'confirmed'
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

  SELECT balance_after
  INTO v_result
  FROM public.wallet_ledger
  WHERE reference_key = 'order-payment-escrow-' || p_order_id::text;

  RETURN jsonb_build_object(
    'success', true,
    'status', 'completed',
    'payment_id', v_payment_id,
    'payment_ref', 'WALLET-' || UPPER(SUBSTRING(p_order_id::text FROM 1 FOR 8)),
    'wallet_balance', (SELECT balance FROM public.wallets WHERE id = v_wallet.id),
    'escrow_amount', v_total
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.sync_payment_split_on_restaurant_confirmation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_split RECORD;
  v_order RECORD;
  v_restaurant_owner_id UUID;
  v_restaurant_wallet RECORD;
BEGIN
  IF NEW.status = 'accepted' AND COALESCE(OLD.status, '') <> 'accepted' THEN
    SELECT *
    INTO v_split
    FROM public.payment_splits
    WHERE order_id = NEW.id
    FOR UPDATE;

    IF FOUND AND COALESCE(v_split.status, '') = 'escrowed' THEN
      SELECT id, restaurant_id
      INTO v_order
      FROM public.orders
      WHERE id = NEW.id;

      SELECT owner_id
      INTO v_restaurant_owner_id
      FROM public.restaurants
      WHERE id = v_order.restaurant_id;

      IF v_restaurant_owner_id IS NOT NULL AND COALESCE(v_split.restaurant_amount, 0) > 0 THEN
        SELECT id, balance
        INTO v_restaurant_wallet
        FROM public.wallets
        WHERE user_id = v_restaurant_owner_id
        FOR UPDATE;

        IF NOT FOUND THEN
          INSERT INTO public.wallets (user_id, balance, currency, is_active, created_at, updated_at)
          VALUES (v_restaurant_owner_id, 0, 'MZN', TRUE, NOW(), NOW())
          RETURNING id, balance INTO v_restaurant_wallet;
        END IF;

        PERFORM public.apply_wallet_ledger_entry(
          p_wallet_id := v_restaurant_wallet.id,
          p_user_id := v_restaurant_owner_id,
          p_order_id := NEW.id,
          p_direction := 'credit',
          p_entry_type := 'restaurant_confirmation_settlement',
          p_amount := COALESCE(v_split.restaurant_amount, 0),
          p_reference_key := 'restaurant-confirmation-' || NEW.id::text,
          p_metadata := jsonb_build_object(
            'source', 'escrow',
            'stage', 'restaurant_confirmation',
            'platform_food_fee', COALESCE(v_split.restaurant_platform_fee, 0)
          ),
          p_status := 'confirmed'
        );
      END IF;

      UPDATE public.payment_splits
      SET status = 'restaurant_confirmed',
          restaurant_confirmed_at = COALESCE(restaurant_confirmed_at, NOW())
      WHERE order_id = NEW.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
CREATE OR REPLACE FUNCTION public.process_delivery_settlement(
  p_order_id UUID,
  p_customer_id UUID,
  p_platform_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_split RECORD;
  v_total NUMERIC;
  v_delivery_fee NUMERIC;
  v_food_platform_fee NUMERIC;
  v_delivery_platform_fee NUMERIC;
  v_total_platform_fee NUMERIC;
  v_courier_amount NUMERIC;
  v_courier_wallet RECORD;
  v_platform_wallet RECORD;
BEGIN
  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND COALESCE(client_id, customer_id) = p_customer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF v_order.status <> 'in_transit' THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  SELECT *
  INTO v_split
  FROM public.payment_splits
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF v_split.id IS NULL THEN
    RAISE EXCEPTION 'payment_split_not_found';
  END IF;

  IF COALESCE(v_split.status, '') = 'completed' THEN
    RETURN jsonb_build_object('success', true, 'duplicate', true, 'status', 'completed');
  END IF;

  v_total := COALESCE(v_order.total_amount, 0);
  v_delivery_fee := COALESCE(v_order.delivery_fee, 0);
  v_food_platform_fee := COALESCE(v_split.restaurant_platform_fee, 0);
  v_delivery_platform_fee := COALESCE(v_split.courier_platform_fee, 0);
  v_total_platform_fee := ROUND((v_food_platform_fee + v_delivery_platform_fee)::numeric, 2);
  v_courier_amount := COALESCE(v_split.courier_amount, ROUND((v_delivery_fee - v_delivery_platform_fee)::numeric, 2));

  IF v_order.courier_id IS NOT NULL AND v_courier_amount > 0 THEN
    SELECT id, balance
    INTO v_courier_wallet
    FROM public.wallets
    WHERE user_id = v_order.courier_id
    FOR UPDATE;

    IF NOT FOUND THEN
      INSERT INTO public.wallets (user_id, balance, currency, is_active, created_at, updated_at)
      VALUES (v_order.courier_id, 0, 'MZN', TRUE, NOW(), NOW())
      RETURNING id, balance INTO v_courier_wallet;
    END IF;

    PERFORM public.apply_wallet_ledger_entry(
      p_wallet_id := v_courier_wallet.id,
      p_user_id := v_order.courier_id,
      p_order_id := p_order_id,
      p_direction := 'credit',
      p_entry_type := 'courier_settlement',
      p_amount := v_courier_amount,
      p_reference_key := 'courier-settlement-' || p_order_id::text,
      p_metadata := jsonb_build_object(
        'source', 'escrow',
        'delivery_fee', v_delivery_fee,
        'platform_fee', v_delivery_platform_fee
      ),
      p_status := 'confirmed'
    );
  END IF;

  IF p_platform_user_id IS NOT NULL AND v_total_platform_fee > 0 THEN
    SELECT id, balance
    INTO v_platform_wallet
    FROM public.wallets
    WHERE user_id = p_platform_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
      INSERT INTO public.wallets (user_id, balance, currency, is_active, created_at, updated_at)
      VALUES (p_platform_user_id, 0, 'MZN', TRUE, NOW(), NOW())
      RETURNING id, balance INTO v_platform_wallet;
    END IF;

    PERFORM public.apply_wallet_ledger_entry(
      p_wallet_id := v_platform_wallet.id,
      p_user_id := p_platform_user_id,
      p_order_id := p_order_id,
      p_direction := 'credit',
      p_entry_type := 'platform_fee_settlement',
      p_amount := v_total_platform_fee,
      p_reference_key := 'platform-settlement-' || p_order_id::text,
      p_metadata := jsonb_build_object(
        'food_fee', v_food_platform_fee,
        'delivery_fee', v_delivery_platform_fee
      ),
      p_status := 'confirmed'
    );
  END IF;

  PERFORM public.apply_wallet_ledger_entry(
    p_wallet_id := NULL,
    p_user_id := NULL,
    p_order_id := p_order_id,
    p_direction := 'debit',
    p_entry_type := 'escrow_release',
    p_amount := v_total,
    p_reference_key := 'escrow-release-' || p_order_id::text,
    p_metadata := jsonb_build_object(
      'courier_amount', v_courier_amount,
      'platform_food_fee', v_food_platform_fee,
      'platform_delivery_fee', v_delivery_platform_fee
    ),
    p_status := 'confirmed'
  );

  UPDATE public.orders
  SET status = 'delivered',
      updated_at = NOW()
  WHERE id = p_order_id;

  UPDATE public.payments
  SET status = 'completed',
      settled_at = NOW(),
      updated_at = NOW()
  WHERE order_id = p_order_id;

  UPDATE public.payment_splits
  SET platform_fee = v_total_platform_fee,
      courier_amount = v_courier_amount,
      escrow_amount = 0,
      status = 'completed',
      settled_at = NOW()
  WHERE order_id = p_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'status', 'completed',
    'courier_amount', v_courier_amount,
    'platform_fee', v_total_platform_fee
  );
END;
$$;
COMMIT;
