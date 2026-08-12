BEGIN;
CREATE OR REPLACE FUNCTION public.ensure_financial_account(
  p_account_code TEXT,
  p_account_name TEXT,
  p_account_type TEXT,
  p_owner_type TEXT,
  p_owner_id UUID DEFAULT NULL,
  p_currency TEXT DEFAULT 'MZN',
  p_is_system_account BOOLEAN DEFAULT FALSE,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_id UUID;
BEGIN
  SELECT id
  INTO v_account_id
  FROM public.financial_accounts
  WHERE account_code = p_account_code
  LIMIT 1
  FOR UPDATE;

  IF v_account_id IS NULL THEN
    INSERT INTO public.financial_accounts (
      account_code,
      account_name,
      account_type,
      owner_type,
      owner_id,
      currency,
      is_system_account,
      metadata
    ) VALUES (
      p_account_code,
      p_account_name,
      p_account_type,
      p_owner_type,
      p_owner_id,
      COALESCE(NULLIF(p_currency, ''), 'MZN'),
      p_is_system_account,
      COALESCE(p_metadata, '{}'::jsonb)
    )
    RETURNING id INTO v_account_id;
  ELSE
    UPDATE public.financial_accounts
    SET account_name = p_account_name,
        account_type = p_account_type,
        owner_type = p_owner_type,
        owner_id = p_owner_id,
        currency = COALESCE(NULLIF(p_currency, ''), 'MZN'),
        is_system_account = p_is_system_account,
        metadata = COALESCE(public.financial_accounts.metadata, '{}'::jsonb) || COALESCE(p_metadata, '{}'::jsonb),
        updated_at = NOW()
    WHERE id = v_account_id;
  END IF;

  RETURN v_account_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.upsert_payout(
  p_order_id UUID,
  p_payout_type TEXT,
  p_entity_type TEXT,
  p_entity_id UUID,
  p_amount NUMERIC,
  p_currency TEXT,
  p_idempotency_key TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payout_id UUID;
BEGIN
  SELECT id
  INTO v_payout_id
  FROM public.payouts
  WHERE idempotency_key = p_idempotency_key
  LIMIT 1
  FOR UPDATE;

  IF v_payout_id IS NULL THEN
    INSERT INTO public.payouts (
      order_id,
      payout_type,
      entity_type,
      entity_id,
      amount,
      currency,
      status,
      idempotency_key,
      metadata,
      processed_at
    ) VALUES (
      p_order_id,
      p_payout_type,
      p_entity_type,
      p_entity_id,
      COALESCE(p_amount, 0),
      COALESCE(NULLIF(p_currency, ''), 'MZN'),
      'paid',
      p_idempotency_key,
      COALESCE(p_metadata, '{}'::jsonb),
      NOW()
    )
    RETURNING id INTO v_payout_id;
  ELSE
    UPDATE public.payouts
    SET amount = COALESCE(p_amount, 0),
        currency = COALESCE(NULLIF(p_currency, ''), 'MZN'),
        status = 'paid',
        metadata = COALESCE(public.payouts.metadata, '{}'::jsonb) || COALESCE(p_metadata, '{}'::jsonb),
        processed_at = COALESCE(public.payouts.processed_at, NOW()),
        updated_at = NOW()
    WHERE id = v_payout_id;
  END IF;

  RETURN v_payout_id;
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
  v_split RECORD;
  v_snapshot RECORD;
  v_total NUMERIC;
  v_delivery NUMERIC;
  v_food NUMERIC;
  v_wallet_before NUMERIC;
  v_wallet_after NUMERIC;
  v_payment_id UUID;
  v_currency TEXT;
  v_platform_food_fee NUMERIC;
  v_platform_delivery_fee NUMERIC;
  v_restaurant_amount NUMERIC;
  v_courier_amount NUMERIC;
  v_payment_idempotency_key TEXT;
  v_ledger_idempotency_key TEXT;
  v_idempotency RECORD;
  v_wallet_account_id UUID;
  v_escrow_account_id UUID;
  v_entry_group_id UUID;
  v_response JSONB;
BEGIN
  v_payment_idempotency_key := 'payment:create:' || p_order_id::text;
  v_ledger_idempotency_key := 'escrow:hold:' || p_order_id::text;

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
  INTO v_idempotency
  FROM public.idempotency_keys
  WHERE scope = 'payment'
    AND idempotency_key = v_payment_idempotency_key
  FOR UPDATE;

  IF FOUND AND v_idempotency.status = 'completed' THEN
    RETURN v_idempotency.response_payload;
  END IF;

  IF NOT FOUND THEN
    INSERT INTO public.idempotency_keys (
      scope,
      idempotency_key,
      request_hash,
      status
    ) VALUES (
      'payment',
      v_payment_idempotency_key,
      md5(COALESCE(p_order_id::text, '') || ':' || COALESCE(p_user_id::text, '')),
      'started'
    );
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

  IF FOUND AND LOWER(COALESCE(v_payment.status, '')) IN ('authorized', 'completed', 'paid') THEN
    v_response := jsonb_build_object(
      'success', true,
      'status', 'authorized',
      'payment_status', 'authorized',
      'funds_status', COALESCE(NULLIF(v_order.funds_status, ''), 'held_in_escrow'),
      'payment_id', v_payment.id,
      'payment_ref', COALESCE(v_payment.payment_ref, v_payment.transaction_id, ('WALLET-' || LEFT(p_order_id::text, 8))),
      'wallet_balance', COALESCE(v_wallet.balance, 0),
      'escrow_amount', COALESCE(v_order.total_amount, v_order.total, 0),
      'currency', COALESCE(NULLIF(v_order.currency, ''), 'MZN')
    );

    UPDATE public.idempotency_keys
    SET status = 'completed',
        resource_type = 'payment',
        resource_id = v_payment.id,
        response_payload = v_response
    WHERE scope = 'payment'
      AND idempotency_key = v_payment_idempotency_key;

    RETURN v_response;
  END IF;

  v_total := COALESCE(v_order.total_amount, v_order.total, 0);
  v_delivery := COALESCE(v_order.delivery_fee, 0);
  v_food := GREATEST(v_total - v_delivery, 0);
  v_currency := COALESCE(NULLIF(v_order.currency, ''), 'MZN');

  IF COALESCE(v_wallet.balance, 0) < v_total THEN
    UPDATE public.idempotency_keys
    SET status = 'failed',
        response_payload = jsonb_build_object(
          'success', false,
          'error', 'insufficient_balance'
        )
    WHERE scope = 'payment'
      AND idempotency_key = v_payment_idempotency_key;

    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  v_wallet_before := COALESCE(v_wallet.balance, 0);
  v_wallet_after := ROUND((v_wallet_before - v_total)::numeric, 2);

  UPDATE public.wallets
  SET balance = v_wallet_after,
      updated_at = NOW()
  WHERE id = v_wallet.id;

  PERFORM public.apply_wallet_ledger_entry(
    p_wallet_id := v_wallet.id,
    p_user_id := p_user_id,
    p_order_id := p_order_id,
    p_direction := 'debit',
    p_entry_type := 'order_payment_escrow',
    p_amount := v_total,
    p_reference_key := 'wallet-debit-' || p_order_id::text,
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
    p_reference_key := 'escrow-credit-' || p_order_id::text,
    p_metadata := jsonb_build_object('source', 'wallet_internal', 'stage', 'escrow_reserved'),
    p_status := 'confirmed'
  );

  v_platform_food_fee := ROUND((v_food * 0.06)::numeric, 2);
  v_platform_delivery_fee := ROUND((v_delivery * 0.05)::numeric, 2);
  v_restaurant_amount := ROUND((v_food - v_platform_food_fee)::numeric, 2);
  v_courier_amount := ROUND((v_delivery - v_platform_delivery_fee)::numeric, 2);

  IF v_payment.id IS NULL THEN
    INSERT INTO public.payments (
      id, order_id, amount, provider, payment_ref, payment_method, status,
      transaction_id, gateway_fee, created_at, updated_at, idempotency_key,
      currency, authorized_at
    ) VALUES (
      gen_random_uuid(),
      p_order_id,
      v_total,
      'internal_wallet',
      'WALLET-' || UPPER(SUBSTRING(p_order_id::text FROM 1 FOR 8)),
      'wallet',
      'authorized',
      'WALLET-' || UPPER(SUBSTRING(p_order_id::text FROM 1 FOR 8)),
      0,
      NOW(),
      NOW(),
      v_payment_idempotency_key,
      v_currency,
      NOW()
    )
    RETURNING id INTO v_payment_id;
  ELSE
    UPDATE public.payments
    SET amount = v_total,
        provider = 'internal_wallet',
        payment_method = 'wallet',
        status = 'authorized',
        gateway_fee = 0,
        updated_at = NOW(),
        idempotency_key = COALESCE(idempotency_key, v_payment_idempotency_key),
        currency = COALESCE(NULLIF(currency, ''), v_currency),
        authorized_at = COALESCE(authorized_at, NOW())
    WHERE id = v_payment.id
    RETURNING id INTO v_payment_id;
  END IF;

  SELECT *
  INTO v_split
  FROM public.payment_splits
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF v_split.id IS NULL THEN
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
    );
  ELSE
    UPDATE public.payment_splits
    SET total_amount = v_total,
        platform_fee = v_platform_food_fee + v_platform_delivery_fee,
        restaurant_amount = v_restaurant_amount,
        courier_amount = v_courier_amount,
        escrow_amount = v_total,
        gateway_fee = 0,
        restaurant_fee_percent = 0.06,
        courier_fee_percent = 0.05,
        restaurant_platform_fee = v_platform_food_fee,
        courier_platform_fee = v_platform_delivery_fee,
        status = 'escrowed'
    WHERE id = v_split.id;
  END IF;

  BEGIN
    EXECUTE 'ALTER TABLE public.orders DISABLE TRIGGER USER';
    UPDATE public.orders
    SET status = 'paid',
        payment_status = 'authorized',
        funds_status = 'held_in_escrow',
        currency = COALESCE(NULLIF(currency, ''), v_currency),
        updated_at = NOW()
    WHERE id = p_order_id;
    EXECUTE 'ALTER TABLE public.orders ENABLE TRIGGER USER';
  EXCEPTION WHEN OTHERS THEN
    EXECUTE 'ALTER TABLE public.orders ENABLE TRIGGER USER';
    RAISE;
  END;

  SELECT *
  INTO v_snapshot
  FROM public.order_financial_snapshots
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF v_snapshot.id IS NULL THEN
    INSERT INTO public.order_financial_snapshots (
      order_id,
      currency,
      subtotal,
      delivery_fee,
      total_amount,
      platform_commission_amount,
      platform_delivery_fee_amount,
      restaurant_net_amount,
      courier_net_amount,
      gateway_fee_amount,
      escrow_amount,
      metadata
    ) VALUES (
      p_order_id,
      v_currency,
      v_food,
      v_delivery,
      v_total,
      v_platform_food_fee,
      v_platform_delivery_fee,
      v_restaurant_amount,
      v_courier_amount,
      0,
      v_total,
      jsonb_build_object(
        'source', 'process_wallet_order_payment',
        'payment_status', 'authorized',
        'funds_status', 'held_in_escrow'
      )
    );
  ELSE
    UPDATE public.order_financial_snapshots
    SET currency = v_currency,
        subtotal = v_food,
        delivery_fee = v_delivery,
        total_amount = v_total,
        platform_commission_amount = v_platform_food_fee,
        platform_delivery_fee_amount = v_platform_delivery_fee,
        restaurant_net_amount = v_restaurant_amount,
        courier_net_amount = v_courier_amount,
        gateway_fee_amount = 0,
        escrow_amount = v_total,
        metadata = COALESCE(public.order_financial_snapshots.metadata, '{}'::jsonb) || jsonb_build_object(
          'source', 'process_wallet_order_payment',
          'payment_status', 'authorized',
          'funds_status', 'held_in_escrow'
        )
    WHERE id = v_snapshot.id;
  END IF;

  v_wallet_account_id := public.ensure_financial_account(
    p_account_code := 'WALLET_' || replace(v_wallet.id::text, '-', ''),
    p_account_name := 'Wallet ' || LEFT(v_wallet.id::text, 8),
    p_account_type := 'liability',
    p_owner_type := 'wallet',
    p_owner_id := v_wallet.id,
    p_currency := v_currency,
    p_metadata := jsonb_build_object('wallet_id', v_wallet.id, 'user_id', p_user_id)
  );

  v_escrow_account_id := public.ensure_financial_account(
    p_account_code := 'SYS_ESCROW_' || v_currency,
    p_account_name := 'System Escrow ' || v_currency,
    p_account_type := 'liability',
    p_owner_type := 'system',
    p_owner_id := NULL,
    p_currency := v_currency,
    p_is_system_account := TRUE,
    p_metadata := jsonb_build_object('purpose', 'escrow')
  );

  v_entry_group_id := gen_random_uuid();

  IF NOT EXISTS (
    SELECT 1
    FROM public.financial_ledger_entries
    WHERE idempotency_key = v_ledger_idempotency_key
  ) THEN
    INSERT INTO public.financial_ledger_entries (
      entry_group_id,
      idempotency_key,
      order_id,
      payment_id,
      account_id,
      direction,
      amount,
      currency,
      entry_type,
      reference_type,
      reference_id,
      metadata
    ) VALUES
      (
        v_entry_group_id,
        v_ledger_idempotency_key,
        p_order_id,
        v_payment_id,
        v_wallet_account_id,
        'debit',
        v_total,
        v_currency,
        'escrow_hold',
        'wallet',
        v_wallet.id,
        jsonb_build_object('side', 'wallet_reserve', 'user_id', p_user_id)
      ),
      (
        v_entry_group_id,
        v_ledger_idempotency_key,
        p_order_id,
        v_payment_id,
        v_escrow_account_id,
        'credit',
        v_total,
        v_currency,
        'escrow_hold',
        'order',
        p_order_id,
        jsonb_build_object('side', 'escrow_liability', 'user_id', p_user_id)
      );
  END IF;

  INSERT INTO public.order_events (
    order_id,
    event_type,
    old_status,
    new_status,
    metadata
  ) VALUES (
    p_order_id,
    'status_changed',
    v_order.status,
    'paid',
    jsonb_build_object(
      'payment_status', 'authorized',
      'funds_status', 'held_in_escrow',
      'source', 'process_wallet_order_payment',
      'payment_id', v_payment_id
    )
  );

  v_response := jsonb_build_object(
    'success', true,
    'status', 'authorized',
    'payment_status', 'authorized',
    'funds_status', 'held_in_escrow',
    'payment_id', v_payment_id,
    'payment_ref', 'WALLET-' || UPPER(SUBSTRING(p_order_id::text FROM 1 FOR 8)),
    'wallet_balance', v_wallet_after,
    'escrow_amount', v_total,
    'currency', v_currency
  );

  UPDATE public.idempotency_keys
  SET status = 'completed',
      resource_type = 'payment',
      resource_id = v_payment_id,
      response_payload = v_response
  WHERE scope = 'payment'
    AND idempotency_key = v_payment_idempotency_key;

  RETURN v_response;
END;
$$;
COMMIT;
