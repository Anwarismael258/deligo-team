BEGIN;
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
  v_effective_user_id UUID := p_user_id;
  v_before NUMERIC := NULL;
  v_after NUMERIC := NULL;
  v_delta NUMERIC;
  v_entry_id UUID;
  v_available_before NUMERIC := NULL;
  v_available_after NUMERIC := NULL;
  v_pending_before NUMERIC := NULL;
  v_pending_after NUMERIC := NULL;
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
    PERFORM pg_advisory_xact_lock(hashtextextended(p_reference_key, 0));

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
    SELECT id, user_id, balance, available_balance, pending_balance
    INTO v_wallet
    FROM public.wallets
    WHERE id = p_wallet_id
    FOR UPDATE;

    IF v_wallet.id IS NULL THEN
      RAISE EXCEPTION 'wallet_not_found';
    END IF;

    v_effective_user_id := COALESCE(p_user_id, v_wallet.user_id);
    v_before := COALESCE(v_wallet.balance, 0);
    v_pending_before := COALESCE(v_wallet.pending_balance, 0);
    v_available_before := COALESCE(v_wallet.available_balance, 0);

    IF ABS((v_available_before + v_pending_before) - v_before) > 0.009 THEN
      IF p_entry_type = 'order_payment_escrow'
         AND p_direction = 'debit'
         AND p_status = 'confirmed' THEN
        v_available_before := GREATEST(
          v_available_before,
          GREATEST(v_before - v_pending_before, 0)
        );
      ELSE
        v_available_before := GREATEST(v_before - v_pending_before, 0);
      END IF;
    END IF;

    v_delta := CASE WHEN p_direction = 'credit' THEN p_amount ELSE -p_amount END;

    IF p_status = 'confirmed' THEN
      v_available_after := ROUND((v_available_before + v_delta)::numeric, 2);
      v_pending_after := v_pending_before;
      IF p_direction = 'debit' AND NOT p_allow_negative AND v_available_after < 0 THEN
        RAISE EXCEPTION 'insufficient_available_balance';
      END IF;
      v_after := ROUND((v_available_after + v_pending_after)::numeric, 2);

      UPDATE public.wallets
      SET available_balance = v_available_after,
          pending_balance = v_pending_after,
          balance = v_after,
          updated_at = NOW()
      WHERE id = p_wallet_id;
    ELSIF p_status = 'pending' THEN
      v_available_after := v_available_before;
      v_pending_after := ROUND(
        (
          v_pending_before +
          CASE WHEN p_direction = 'credit' THEN p_amount ELSE 0 END
        )::numeric,
        2
      );
      v_after := ROUND((v_available_after + v_pending_after)::numeric, 2);

      UPDATE public.wallets
      SET available_balance = v_available_after,
          pending_balance = v_pending_after,
          balance = v_after,
          updated_at = NOW()
      WHERE id = p_wallet_id;
    ELSE
      v_available_after := v_available_before;
      v_pending_after := v_pending_before;
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
    v_effective_user_id,
    p_order_id,
    p_payment_id,
    p_direction,
    p_entry_type,
    p_amount,
    v_before,
    v_after,
    COALESCE(
      p_metadata,
      '{}'::jsonb
    ) || jsonb_build_object(
      'available_balance_before', v_available_before,
      'available_balance_after', v_available_after,
      'pending_balance_before', v_pending_before,
      'pending_balance_after', v_pending_after
    ),
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
    'available_balance_before', v_available_before,
    'available_balance_after', v_available_after,
    'pending_balance_before', v_pending_before,
    'pending_balance_after', v_pending_after,
    'status', p_status
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.process_order_cancellation(
  p_order_id UUID,
  p_user_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_payment_split RECORD;
  v_payment RECORD;
  v_client_wallet public.wallets%rowtype;
  v_restaurant_wallet public.wallets%rowtype;
  v_restaurant_owner UUID;
  v_restaurant_name TEXT := 'o restaurante';
  v_refund_percent NUMERIC := 0;
  v_refund_amount NUMERIC := 0;
  v_recovery_from_restaurant NUMERIC := 0;
  v_currency TEXT := 'MZN';
  v_message TEXT := '';
  v_cancel_count INTEGER := 0;
  v_points INTEGER := 0;
  v_is_test_user BOOLEAN := FALSE;
  v_skip_limit BOOLEAN := FALSE;
  v_is_timeout BOOLEAN := FALSE;
  v_client_entry_type TEXT := 'order_cancellation_refund';
  v_idempotency_key TEXT;
  v_idempotency RECORD;
  v_client_account_id UUID;
  v_escrow_account_id UUID;
  v_entry_group_id UUID := gen_random_uuid();
  v_response JSONB;
BEGIN
  v_is_timeout := p_reason IN ('restaurant_timeout', 'system_timeout');
  v_skip_limit := v_is_timeout;
  IF v_is_timeout THEN
    v_client_entry_type := 'order_timeout_refund';
  END IF;

  v_idempotency_key := 'refund:' || p_order_id::text || ':' || COALESCE(NULLIF(p_reason, ''), 'customer_cancellation');

  SELECT *
  INTO v_idempotency
  FROM public.idempotency_keys
  WHERE scope = 'refund'
    AND idempotency_key = v_idempotency_key
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
      'refund',
      v_idempotency_key,
      md5(COALESCE(p_order_id::text, '') || ':' || COALESCE(p_user_id::text, '') || ':' || COALESCE(p_reason, '')),
      'started'
    );
  END IF;

  SELECT COALESCE(p.is_test_user, FALSE)
  INTO v_is_test_user
  FROM public.profiles p
  WHERE p.id = p_user_id
  LIMIT 1;

  IF NOT v_is_test_user AND NOT v_skip_limit THEN
    SELECT COUNT(*)
    INTO v_cancel_count
    FROM public.orders
    WHERE (client_id = p_user_id OR customer_id = p_user_id)
      AND status = 'cancelled'
      AND created_at >= now() - interval '24 hours'
      AND COALESCE(cancellation_reason, 'customer_cancellation') NOT IN (
        'restaurant_timeout',
        'system_timeout'
      );

    IF v_cancel_count >= 999 THEN
      RAISE EXCEPTION 'daily_cancellation_limit_reached';
    END IF;
  END IF;

  SELECT o.*, COALESCE(r.name, 'o restaurante') AS restaurant_name
  INTO v_order
  FROM public.orders o
  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.id = p_order_id
    AND (o.client_id = p_user_id OR o.customer_id = p_user_id)
  FOR UPDATE OF o;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  v_restaurant_name := COALESCE(v_order.restaurant_name, 'o restaurante');
  v_currency := COALESCE(NULLIF(v_order.currency, ''), 'MZN');

  SELECT *
  INTO v_payment_split
  FROM public.payment_splits
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF v_is_timeout
     AND (
       COALESCE(v_order.status, '') NOT IN ('pending', 'paid', 'payment_authorized')
       OR COALESCE(v_payment_split.status, '') IN ('restaurant_confirmed', 'completed')
     ) THEN
    v_response := jsonb_build_object(
      'success', true,
      'skipped', true,
      'status', v_order.status,
      'refund_percent', 0,
      'refund_amount', 0,
      'message', 'Timeout ignorado porque o pedido ja saiu da espera do restaurante.'
    );

    UPDATE public.idempotency_keys
    SET status = 'completed',
        response_payload = v_response
    WHERE scope = 'refund'
      AND idempotency_key = v_idempotency_key;

    RETURN v_response;
  END IF;

  IF v_order.status IN ('in_transit', 'courier_assigned', 'on_the_way', 'arrived', 'delivered', 'completed') THEN
    RAISE EXCEPTION 'cancellation_not_allowed';
  END IF;

  IF v_order.status = 'cancelled' THEN
    v_response := jsonb_build_object(
      'success', true,
      'status', 'cancelled',
      'refund_percent', 0,
      'refund_amount', 0,
      'message', 'Pedido ja estava cancelado.'
    );

    UPDATE public.idempotency_keys
    SET status = 'completed',
        response_payload = v_response
    WHERE scope = 'refund'
      AND idempotency_key = v_idempotency_key;

    RETURN v_response;
  END IF;

  CASE v_order.status
    WHEN 'pending' THEN
      v_refund_percent := CASE
        WHEN COALESCE(v_order.payment_status, 'pending') IN ('authorized', 'paid', 'completed') THEN 1.0
        ELSE 0.0
      END;
      v_points := 1;
    WHEN 'payment_authorized' THEN
      v_refund_percent := 1.0;
      v_points := 2;
    WHEN 'paid' THEN
      v_refund_percent := 1.0;
      v_points := 2;
    WHEN 'accepted' THEN
      v_refund_percent := 0.8;
      v_points := 8;
    WHEN 'preparing' THEN
      v_refund_percent := 0.0;
      v_points := 12;
    ELSE
      v_refund_percent := 0.0;
      v_points := 5;
  END CASE;

  v_refund_amount := ROUND(COALESCE(v_order.total_amount, 0) * v_refund_percent, 2);

  SELECT *
  INTO v_payment
  FROM public.payments
  WHERE order_id = p_order_id
  ORDER BY created_at DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF v_refund_amount > 0 THEN
    v_client_wallet := public.ensure_user_wallet(p_user_id, v_currency);

    IF v_order.status = 'accepted' AND v_payment_split.status = 'restaurant_confirmed' THEN
      SELECT owner_id
      INTO v_restaurant_owner
      FROM public.restaurants
      WHERE id = v_order.restaurant_id
      LIMIT 1;

      IF v_restaurant_owner IS NOT NULL THEN
        v_restaurant_wallet := public.ensure_user_wallet(v_restaurant_owner, v_currency);
        v_recovery_from_restaurant := LEAST(
          ROUND(COALESCE(v_payment_split.restaurant_amount, 0), 2),
          ROUND(COALESCE(v_restaurant_wallet.available_balance, v_restaurant_wallet.balance, 0), 2),
          v_refund_amount
        );

        IF v_recovery_from_restaurant > 0 THEN
          PERFORM public.apply_wallet_ledger_entry(
            p_wallet_id := v_restaurant_wallet.id,
            p_user_id := v_restaurant_owner,
            p_order_id := p_order_id,
            p_payment_id := v_payment.id,
            p_direction := 'debit',
            p_entry_type := 'restaurant_cancellation_reversal',
            p_amount := v_recovery_from_restaurant,
            p_reference_key := 'restaurant-recovery-' || p_order_id::text,
            p_metadata := jsonb_build_object(
              'reason', COALESCE(p_reason, 'customer_cancellation'),
              'refund_percent', v_refund_percent
            ),
            p_status := 'confirmed'
          );
        END IF;
      END IF;
    END IF;

    PERFORM public.apply_wallet_ledger_entry(
      p_wallet_id := v_client_wallet.id,
      p_user_id := p_user_id,
      p_order_id := p_order_id,
      p_payment_id := v_payment.id,
      p_direction := 'credit',
      p_entry_type := v_client_entry_type,
      p_amount := v_refund_amount,
      p_reference_key := 'refund-wallet-' || p_order_id::text || '-' || replace(COALESCE(p_reason, 'customer_cancellation'), ' ', '_'),
      p_metadata := jsonb_build_object(
        'reason', COALESCE(p_reason, 'customer_cancellation'),
        'refund_percent', v_refund_percent,
        'recovered_from_restaurant', v_recovery_from_restaurant
      ),
      p_status := 'confirmed'
    );

    v_client_account_id := public.ensure_financial_account(
      p_account_code := 'USER_WALLET_' || replace(p_user_id::text, '-', ''),
      p_account_name := 'User Wallet ' || LEFT(p_user_id::text, 8),
      p_account_type := 'liability',
      p_owner_type := 'user',
      p_owner_id := p_user_id,
      p_currency := v_currency,
      p_metadata := jsonb_build_object('wallet_id', v_client_wallet.id)
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
        v_idempotency_key,
        p_order_id,
        v_payment.id,
        v_escrow_account_id,
        'debit',
        v_refund_amount,
        v_currency,
        'refund_issued',
        'order',
        p_order_id,
        jsonb_build_object('reason', COALESCE(p_reason, 'customer_cancellation'))
      ),
      (
        v_entry_group_id,
        v_idempotency_key,
        p_order_id,
        v_payment.id,
        v_client_account_id,
        'credit',
        v_refund_amount,
        v_currency,
        'refund_issued',
        'user',
        p_user_id,
        jsonb_build_object('reason', COALESCE(p_reason, 'customer_cancellation'))
      )
    ON CONFLICT DO NOTHING;
  END IF;

  UPDATE public.orders
  SET status = 'cancelled',
      payment_status = CASE
        WHEN v_refund_amount <= 0 THEN COALESCE(payment_status, 'pending')
        WHEN v_refund_amount < COALESCE(total_amount, 0) THEN 'partially_refunded'
        ELSE 'refunded'
      END,
      funds_status = CASE
        WHEN v_refund_amount <= 0 THEN COALESCE(funds_status, 'none')
        WHEN v_refund_amount < COALESCE(total_amount, 0) THEN 'partially_refunded'
        ELSE 'refunded'
      END,
      financial_outcome = CASE
        WHEN v_refund_amount <= 0 THEN financial_outcome
        WHEN v_refund_amount < COALESCE(total_amount, 0) THEN 'partially_refunded'
        ELSE 'refunded'
      END,
      cancellation_reason = COALESCE(p_reason, cancellation_reason, 'customer_cancellation'),
      updated_at = NOW()
  WHERE id = p_order_id;

  IF v_payment_split.order_id IS NOT NULL THEN
    UPDATE public.payment_splits
    SET status = 'cancelled',
        escrow_amount = GREATEST(COALESCE(escrow_amount, 0) - v_refund_amount, 0),
        settled_at = NOW()
    WHERE order_id = p_order_id;
  END IF;

  IF v_payment.id IS NOT NULL AND v_refund_amount > 0 THEN
    UPDATE public.payments
    SET status = CASE
          WHEN v_refund_amount < COALESCE(v_order.total_amount, 0) THEN 'partially_refunded'
          ELSE 'refunded'
        END,
        refunded_at = COALESCE(refunded_at, NOW()),
        updated_at = NOW()
    WHERE id = v_payment.id;
  END IF;

  INSERT INTO public.refunds (
    order_id,
    user_id,
    amount,
    refund_amount,
    refund_percent,
    status,
    reason,
    metadata
  )
  VALUES (
    p_order_id,
    p_user_id,
    v_refund_amount,
    v_refund_amount,
    ROUND(v_refund_percent * 100, 2),
    CASE WHEN v_refund_amount > 0 THEN 'completed' ELSE 'no_refund' END,
    COALESCE(p_reason, 'customer_cancellation'),
    jsonb_build_object(
      'order_status', v_order.status,
      'restaurant_name', v_restaurant_name,
      'recovered_from_restaurant', v_recovery_from_restaurant,
      'idempotency_key', v_idempotency_key,
      'entry_group_id', v_entry_group_id
    )
  );

  INSERT INTO public.order_events (
    order_id,
    event_type,
    old_status,
    new_status,
    metadata
  ) VALUES (
    p_order_id,
    'refund_issued',
    v_order.status,
    'cancelled',
    jsonb_build_object(
      'refund_percent', ROUND(v_refund_percent * 100, 2),
      'refund_amount', v_refund_amount,
      'reason', COALESCE(p_reason, 'customer_cancellation'),
      'entry_group_id', v_entry_group_id
    )
  );

  v_message := CASE
    WHEN v_refund_amount > 0
      THEN 'Pedido cancelado. O valor foi devolvido para a sua carteira.'
    ELSE 'Pedido cancelado.'
  END;

  v_response := jsonb_build_object(
    'success', true,
    'status', 'cancelled',
    'refund_percent', ROUND(v_refund_percent * 100, 2),
    'refund_amount', v_refund_amount,
    'message', v_message,
    'payment_status', CASE
      WHEN v_refund_amount <= 0 THEN COALESCE(v_order.payment_status, 'pending')
      WHEN v_refund_amount < COALESCE(v_order.total_amount, 0) THEN 'partially_refunded'
      ELSE 'refunded'
    END,
    'funds_status', CASE
      WHEN v_refund_amount <= 0 THEN COALESCE(v_order.funds_status, 'none')
      WHEN v_refund_amount < COALESCE(v_order.total_amount, 0) THEN 'partially_refunded'
      ELSE 'refunded'
    END
  );

  UPDATE public.idempotency_keys
  SET status = 'completed',
      resource_type = 'refund',
      resource_id = p_order_id,
      response_payload = v_response
  WHERE scope = 'refund'
    AND idempotency_key = v_idempotency_key;

  RETURN v_response;
END;
$$;
CREATE OR REPLACE FUNCTION public.process_restaurant_confirmation_timeouts()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_user_id UUID;
  v_count INTEGER := 0;
  v_cancel_result JSONB;
BEGIN
  FOR v_order IN
    SELECT o.id, o.client_id, o.customer_id
    FROM public.orders o
    WHERE (
      o.status IN ('paid', 'payment_authorized')
      AND COALESCE(o.updated_at, o.created_at) <= NOW() - INTERVAL '3 minutes'
    ) OR (
      o.status = 'pending'
      AND COALESCE(o.payment_status, 'pending') IN ('paid', 'completed', 'authorized')
      AND COALESCE(o.updated_at, o.created_at) <= NOW() - INTERVAL '3 minutes'
    ) OR (
      o.status = 'pending'
      AND COALESCE(o.payment_status, 'pending') NOT IN ('paid', 'completed', 'authorized')
      AND o.created_at <= NOW() - INTERVAL '15 minutes'
    )
  LOOP
    v_user_id := COALESCE(v_order.client_id, v_order.customer_id);
    IF v_user_id IS NULL THEN
      CONTINUE;
    END IF;

    v_cancel_result := public.process_order_cancellation(
      v_order.id,
      v_user_id,
      'restaurant_timeout'
    );

    IF COALESCE(v_cancel_result ->> 'status', '') = 'cancelled'
       AND COALESCE((v_cancel_result ->> 'skipped')::BOOLEAN, FALSE) = FALSE THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;
COMMIT;
