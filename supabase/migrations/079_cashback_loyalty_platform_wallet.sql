BEGIN;
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
  v_customer_wallet RECORD;
  v_cashback_amount NUMERIC := 0;
  v_eligible_completed_orders INTEGER := 0;
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

  IF p_platform_user_id IS NOT NULL AND v_total >= 800 THEN
    SELECT COUNT(*)
    INTO v_eligible_completed_orders
    FROM public.orders
    WHERE COALESCE(client_id, customer_id) = p_customer_id
      AND id <> p_order_id
      AND COALESCE(total_amount, 0) >= 800
      AND status IN ('delivered', 'completed');

    IF v_eligible_completed_orders >= 8 THEN
      v_cashback_amount := ROUND((v_total * 0.10)::numeric, 2);

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

      IF COALESCE(v_platform_wallet.balance, 0) >= v_cashback_amount THEN
        SELECT id, balance
        INTO v_customer_wallet
        FROM public.wallets
        WHERE user_id = p_customer_id
        FOR UPDATE;

        IF NOT FOUND THEN
          INSERT INTO public.wallets (user_id, balance, currency, is_active, created_at, updated_at)
          VALUES (p_customer_id, 0, 'MZN', TRUE, NOW(), NOW())
          RETURNING id, balance INTO v_customer_wallet;
        END IF;

        PERFORM public.apply_wallet_ledger_entry(
          p_wallet_id := v_platform_wallet.id,
          p_user_id := p_platform_user_id,
          p_order_id := p_order_id,
          p_direction := 'debit',
          p_entry_type := 'cashback_reward',
          p_amount := v_cashback_amount,
          p_reference_key := 'cashback-platform-' || p_order_id::text,
          p_metadata := jsonb_build_object(
            'customer_id', p_customer_id,
            'eligible_completed_orders', v_eligible_completed_orders,
            'rule', 'after_8_orders_above_800'
          ),
          p_status := 'confirmed'
        );

        PERFORM public.apply_wallet_ledger_entry(
          p_wallet_id := v_customer_wallet.id,
          p_user_id := p_customer_id,
          p_order_id := p_order_id,
          p_direction := 'credit',
          p_entry_type := 'cashback_reward',
          p_amount := v_cashback_amount,
          p_reference_key := 'cashback-customer-' || p_order_id::text,
          p_metadata := jsonb_build_object(
            'platform_user_id', p_platform_user_id,
            'eligible_completed_orders', v_eligible_completed_orders,
            'rule', 'after_8_orders_above_800'
          ),
          p_status := 'confirmed'
        );
      END IF;
    END IF;
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
      'platform_delivery_fee', v_delivery_platform_fee,
      'cashback_amount', v_cashback_amount
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
    'platform_fee', v_total_platform_fee,
    'cashback_amount', v_cashback_amount,
    'eligible_completed_orders', v_eligible_completed_orders
  );
END;
$$;
COMMIT;
