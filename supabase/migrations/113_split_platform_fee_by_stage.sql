BEGIN;
CREATE OR REPLACE FUNCTION public.sync_payment_split_on_restaurant_confirmation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_split RECORD;
  v_order RECORD;
  v_restaurant_owner_id UUID;
  v_restaurant_wallet RECORD;
  v_platform_user_id UUID;
  v_platform_wallet RECORD;
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

      SELECT id
      INTO v_platform_user_id
      FROM public.profiles
      WHERE role = 'admin'
      ORDER BY updated_at DESC NULLS LAST, id
      LIMIT 1;

      IF v_platform_user_id IS NOT NULL AND COALESCE(v_split.restaurant_platform_fee, 0) > 0 THEN
        SELECT id, balance
        INTO v_platform_wallet
        FROM public.wallets
        WHERE user_id = v_platform_user_id
        FOR UPDATE;

        IF NOT FOUND THEN
          INSERT INTO public.wallets (user_id, balance, currency, is_active, created_at, updated_at)
          VALUES (v_platform_user_id, 0, 'MZN', TRUE, NOW(), NOW())
          RETURNING id, balance INTO v_platform_wallet;
        END IF;

        PERFORM public.apply_wallet_ledger_entry(
          p_wallet_id := v_platform_wallet.id,
          p_user_id := v_platform_user_id,
          p_order_id := NEW.id,
          p_direction := 'credit',
          p_entry_type := 'platform_food_fee_settlement',
          p_amount := COALESCE(v_split.restaurant_platform_fee, 0),
          p_reference_key := 'platform-food-confirmation-' || NEW.id::text,
          p_metadata := jsonb_build_object(
            'source', 'escrow',
            'stage', 'restaurant_confirmation'
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
  v_total_platform_fee := ROUND(v_delivery_platform_fee::numeric, 2);
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
        'food_fee', 0,
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
  SET platform_fee = ROUND((v_food_platform_fee + v_delivery_platform_fee)::numeric, 2),
      courier_amount = v_courier_amount,
      escrow_amount = 0,
      status = 'completed',
      settled_at = NOW()
  WHERE order_id = p_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'status', 'completed',
    'courier_amount', v_courier_amount,
    'platform_fee', ROUND((v_food_platform_fee + v_delivery_platform_fee)::numeric, 2)
  );
END;
$$;
COMMIT;
