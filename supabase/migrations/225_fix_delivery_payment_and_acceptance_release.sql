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
CREATE OR REPLACE FUNCTION public.process_restaurant_acceptance_release(
  p_order_id UUID,
  p_restaurant_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%rowtype;
  v_split public.payment_splits%rowtype;
  v_snapshot public.order_financial_snapshots%rowtype;
  v_payment public.payments%rowtype;
  v_idempotency RECORD;
  v_actor_id UUID := COALESCE(p_restaurant_user_id, auth.uid());
  v_restaurant_owner UUID;
  v_restaurant_wallet public.wallets%rowtype;
  v_currency TEXT;
  v_restaurant_amount NUMERIC := 0;
  v_remaining_escrow NUMERIC := 0;
  v_payout_id UUID;
  v_idempotency_key TEXT := 'restaurant-acceptance-release:' || p_order_id::text;
  v_response JSONB;
BEGIN
  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  SELECT *
  INTO v_split
  FROM public.payment_splits
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF v_split.id IS NULL THEN
    RAISE EXCEPTION 'payment_split_not_found';
  END IF;

  IF COALESCE(v_split.status, '') IN ('restaurant_confirmed', 'completed') THEN
    RETURN jsonb_build_object(
      'success', true,
      'duplicate', true,
      'status', COALESCE(v_split.status, 'restaurant_confirmed'),
      'restaurant_amount', COALESCE(v_split.restaurant_amount, 0),
      'remaining_escrow_amount', COALESCE(v_split.escrow_amount, 0)
    );
  END IF;

  SELECT owner_id
  INTO v_restaurant_owner
  FROM public.restaurants
  WHERE id = v_order.restaurant_id
  LIMIT 1;

  IF v_restaurant_owner IS NULL THEN
    RAISE EXCEPTION 'restaurant_owner_not_found';
  END IF;

  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  IF v_actor_id <> v_restaurant_owner THEN
    RAISE EXCEPTION 'restaurant_not_authorized';
  END IF;

  SELECT *
  INTO v_idempotency
  FROM public.idempotency_keys
  WHERE scope = 'restaurant_acceptance_release'
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
      'restaurant_acceptance_release',
      v_idempotency_key,
      md5(COALESCE(p_order_id::text, '') || ':' || COALESCE(v_actor_id::text, '')),
      'started'
    );
  END IF;

  SELECT *
  INTO v_snapshot
  FROM public.order_financial_snapshots
  WHERE order_id = p_order_id
  FOR UPDATE;

  SELECT *
  INTO v_payment
  FROM public.payments
  WHERE order_id = p_order_id
  ORDER BY created_at DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  v_currency := COALESCE(
    NULLIF(v_snapshot.currency, ''),
    NULLIF(v_order.currency, ''),
    NULLIF(v_payment.currency, ''),
    'MZN'
  );
  v_restaurant_amount := ROUND(
    COALESCE(v_split.restaurant_amount, v_snapshot.restaurant_net_amount, 0),
    2
  );
  v_remaining_escrow := GREATEST(
    COALESCE(v_split.escrow_amount, COALESCE(v_order.total_amount, v_order.total, 0)) - v_restaurant_amount,
    0
  );

  IF v_restaurant_amount > 0 THEN
    v_restaurant_wallet := public.ensure_user_wallet(v_restaurant_owner, v_currency);

    PERFORM public.apply_wallet_ledger_entry(
      p_wallet_id := v_restaurant_wallet.id,
      p_user_id := v_restaurant_owner,
      p_order_id := p_order_id,
      p_payment_id := v_payment.id,
      p_direction := 'credit',
      p_entry_type := 'restaurant_acceptance_settlement',
      p_amount := v_restaurant_amount,
      p_reference_key := 'restaurant-settlement-' || p_order_id::text,
      p_metadata := jsonb_build_object(
        'source', 'restaurant_acceptance_release',
        'currency', v_currency
      ),
      p_status := 'confirmed'
    );

    v_payout_id := public.upsert_payout(
      p_order_id := p_order_id,
      p_payout_type := 'settlement',
      p_entity_type := 'restaurant',
      p_entity_id := v_restaurant_owner,
      p_amount := v_restaurant_amount,
      p_currency := v_currency,
      p_idempotency_key := 'payout:' || p_order_id::text || ':restaurant',
      p_metadata := jsonb_build_object('source', 'process_restaurant_acceptance_release')
    );
  END IF;

  UPDATE public.payment_splits
  SET status = 'restaurant_confirmed',
      restaurant_confirmed_at = COALESCE(restaurant_confirmed_at, NOW()),
      escrow_amount = v_remaining_escrow
  WHERE order_id = p_order_id;

  IF v_snapshot.id IS NOT NULL THEN
    UPDATE public.order_financial_snapshots
    SET escrow_amount = v_remaining_escrow,
        metadata = COALESCE(public.order_financial_snapshots.metadata, '{}'::jsonb) || jsonb_build_object(
          'restaurant_acceptance_released', true,
          'restaurant_acceptance_released_at', NOW()
        )
    WHERE id = v_snapshot.id;
  END IF;

  v_response := jsonb_build_object(
    'success', true,
    'duplicate', false,
    'status', 'restaurant_confirmed',
    'restaurant_amount', v_restaurant_amount,
    'remaining_escrow_amount', v_remaining_escrow,
    'payout_id', v_payout_id
  );

  UPDATE public.idempotency_keys
  SET status = 'completed',
      resource_type = 'payout',
      resource_id = v_payout_id,
      response_payload = v_response
  WHERE scope = 'restaurant_acceptance_release'
    AND idempotency_key = v_idempotency_key;

  RETURN v_response;
END;
$$;
REVOKE ALL ON FUNCTION public.process_restaurant_acceptance_release(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_restaurant_acceptance_release(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_restaurant_acceptance_release(UUID, UUID) TO service_role;
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
  v_allowed BOOLEAN := FALSE;
  v_order public.orders%rowtype;
  v_previous_status TEXT;
  v_normalized_status TEXT := LOWER(COALESCE(btrim(p_status), ''));
  v_now TIMESTAMPTZ := NOW();
  v_acceptance_release JSONB := '{}'::jsonb;
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
        accepted_at = CASE WHEN v_normalized_status = 'accepted' THEN COALESCE(accepted_at, v_now) ELSE accepted_at END,
        preparing_at = CASE WHEN v_normalized_status = 'preparing' THEN COALESCE(preparing_at, v_now) ELSE preparing_at END,
        ready_at = CASE WHEN v_normalized_status = 'ready' THEN COALESCE(ready_at, v_now) ELSE ready_at END,
        updated_at = v_now
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
    v_acceptance_release := public.process_restaurant_acceptance_release(
      p_order_id := p_order_id,
      p_restaurant_user_id := v_user_id
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
    v_previous_status,
    v_normalized_status,
    jsonb_build_object(
      'payment_status', v_order.payment_status,
      'funds_status', v_order.funds_status,
      'source', 'restaurant_update_order_status',
      'restaurant_user_id', v_user_id,
      'accepted_at', v_order.accepted_at,
      'preparing_at', v_order.preparing_at,
      'ready_at', v_order.ready_at,
      'acceptance_release', COALESCE(v_acceptance_release, '{}'::jsonb)
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
    'funds_status', v_order.funds_status,
    'accepted_at', v_order.accepted_at,
    'preparing_at', v_order.preparing_at,
    'ready_at', v_order.ready_at,
    'acceptance_release', COALESCE(v_acceptance_release, '{}'::jsonb)
  );
END;
$$;
COMMIT;
