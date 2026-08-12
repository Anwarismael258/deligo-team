-- Allow delivery settlement for multiple delivery statuses
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

  IF v_order.status NOT IN ('in_transit', 'arrived', 'on_the_way', 'courier_assigned') THEN
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
        'delivery_fee', v_delivery_fee,
        'platform_fee', v_delivery_platform_fee
      ),
      p_status := 'confirmed'
    );
  END IF;

  UPDATE public.payment_splits
  SET status = 'completed',
      delivered_at = COALESCE(delivered_at, NOW())
  WHERE order_id = p_order_id;

  RETURN jsonb_build_object('success', true, 'status', 'completed');
END;
$$;
