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
  ON CONFLICT (account_code) DO UPDATE
  SET account_name = EXCLUDED.account_name,
      account_type = EXCLUDED.account_type,
      owner_type = EXCLUDED.owner_type,
      owner_id = EXCLUDED.owner_id,
      currency = EXCLUDED.currency,
      is_system_account = EXCLUDED.is_system_account,
      metadata = public.financial_accounts.metadata || EXCLUDED.metadata
  RETURNING id INTO v_account_id;

  RETURN v_account_id;
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

  INSERT INTO public.wallet_ledger (
    wallet_id, user_id, order_id, payment_id, direction, entry_type,
    amount, balance_before, balance_after, metadata, reference_key, status, currency
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
    jsonb_build_object('source', 'wallet_internal', 'stage', 'escrow_reserved'),
    'wallet-debit-' || p_order_id::text,
    'confirmed',
    v_currency
  )
  ON CONFLICT (reference_key) DO NOTHING;

  INSERT INTO public.wallet_ledger (
    wallet_id, user_id, order_id, payment_id, direction, entry_type,
    amount, balance_before, balance_after, metadata, reference_key, status, currency
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
    jsonb_build_object('source', 'wallet_internal', 'stage', 'escrow_reserved'),
    'escrow-credit-' || p_order_id::text,
    'confirmed',
    v_currency
  )
  ON CONFLICT (reference_key) DO NOTHING;

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
  )
  ON CONFLICT (order_id) DO UPDATE SET
    currency = EXCLUDED.currency,
    subtotal = EXCLUDED.subtotal,
    delivery_fee = EXCLUDED.delivery_fee,
    total_amount = EXCLUDED.total_amount,
    platform_commission_amount = EXCLUDED.platform_commission_amount,
    platform_delivery_fee_amount = EXCLUDED.platform_delivery_fee_amount,
    restaurant_net_amount = EXCLUDED.restaurant_net_amount,
    courier_net_amount = EXCLUDED.courier_net_amount,
    gateway_fee_amount = EXCLUDED.gateway_fee_amount,
    escrow_amount = EXCLUDED.escrow_amount,
    metadata = public.order_financial_snapshots.metadata || EXCLUDED.metadata;

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
    )
  ON CONFLICT DO NOTHING;

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
CREATE OR REPLACE FUNCTION public.restaurant_update_order_status(
  p_order_id UUID,
  p_status TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_order RECORD;
  v_allowed BOOLEAN := FALSE;
  v_previous_status TEXT;
  v_normalized_status TEXT := LOWER(COALESCE(TRIM(p_status), ''));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  IF v_normalized_status = '' THEN
    RAISE EXCEPTION 'status_required';
  END IF;

  SELECT o.*
  INTO v_order
  FROM public.orders o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.restaurants r
    WHERE r.id = v_order.restaurant_id
      AND r.owner_id = v_user_id
  )
  INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'restaurant_not_authorized';
  END IF;

  IF v_normalized_status NOT IN ('accepted', 'preparing', 'ready', 'cancelled') THEN
    RAISE EXCEPTION 'invalid_restaurant_status';
  END IF;

  IF NOT public.validate_order_transition(
    COALESCE(v_order.status, ''),
    v_normalized_status,
    COALESCE(v_order.delivery_type, CASE WHEN COALESCE(v_order.delivery_fee, 0) > 0 THEN 'delivery' ELSE 'pickup' END)
  ) THEN
    RAISE EXCEPTION 'invalid_order_transition';
  END IF;

  IF v_normalized_status = 'accepted'
     AND COALESCE(v_order.payment_status, 'pending') NOT IN ('authorized', 'completed', 'paid') THEN
    RAISE EXCEPTION 'payment_not_authorized';
  END IF;

  v_previous_status := v_order.status;

  BEGIN
    EXECUTE 'ALTER TABLE public.orders DISABLE TRIGGER USER';
    UPDATE public.orders
    SET status = v_normalized_status,
        updated_at = NOW()
    WHERE id = p_order_id
      AND status = v_previous_status
    RETURNING * INTO v_order;
    EXECUTE 'ALTER TABLE public.orders ENABLE TRIGGER USER';
  EXCEPTION WHEN OTHERS THEN
    EXECUTE 'ALTER TABLE public.orders ENABLE TRIGGER USER';
    RAISE;
  END;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'concurrent_order_transition';
  END IF;

  IF v_normalized_status = 'accepted' AND COALESCE(v_previous_status, '') <> 'accepted' THEN
    UPDATE public.payment_splits
    SET status = CASE WHEN status = 'escrowed' THEN 'restaurant_confirmed' ELSE status END,
        restaurant_confirmed_at = COALESCE(restaurant_confirmed_at, NOW())
    WHERE order_id = p_order_id;
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
    v_previous_status,
    v_normalized_status,
    jsonb_build_object(
      'payment_status', v_order.payment_status,
      'funds_status', v_order.funds_status,
      'source', 'restaurant_update_order_status',
      'restaurant_user_id', v_user_id
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order.id,
    'status', v_order.status,
    'updated_at', v_order.updated_at,
    'delivery_type', v_order.delivery_type,
    'delivery_fee', v_order.delivery_fee,
    'payment_status', v_order.payment_status,
    'funds_status', v_order.funds_status
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.client_confirm_pickup(
  p_order_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_order public.orders%rowtype;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF v_user_id <> COALESCE(v_order.client_id, v_order.customer_id) THEN
    RAISE EXCEPTION 'not_order_owner';
  END IF;

  IF COALESCE(v_order.delivery_type, '') <> 'pickup'
     AND COALESCE(v_order.delivery_fee, 0) > 0 THEN
    RAISE EXCEPTION 'order_not_pickup';
  END IF;

  IF v_order.status IN ('completed', 'delivered') THEN
    RETURN to_jsonb(v_order);
  END IF;

  IF v_order.status <> 'ready' THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  BEGIN
    EXECUTE 'ALTER TABLE public.orders DISABLE TRIGGER USER';
    UPDATE public.orders
    SET status = 'completed',
        confirmed_by_customer = TRUE,
        order_completed_at = COALESCE(order_completed_at, NOW()),
        updated_at = NOW()
    WHERE id = p_order_id
    RETURNING * INTO v_order;
    EXECUTE 'ALTER TABLE public.orders ENABLE TRIGGER USER';
  EXCEPTION WHEN OTHERS THEN
    EXECUTE 'ALTER TABLE public.orders ENABLE TRIGGER USER';
    RAISE;
  END;

  RETURN to_jsonb(v_order);
END;
$$;
REVOKE ALL ON FUNCTION public.ensure_financial_account(TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_financial_account(TEXT, TEXT, TEXT, TEXT, UUID, TEXT, BOOLEAN, JSONB) TO authenticated, service_role;
COMMIT;
