-- Distinguish restaurant-timeout refunds from manual cancellations

CREATE OR REPLACE FUNCTION public.process_order_cancellation(
  p_order_id UUID,
  p_user_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order RECORD;
  v_payment_split RECORD;
  v_client_wallet RECORD;
  v_restaurant_wallet RECORD;
  v_restaurant_owner UUID;
  v_restaurant_name TEXT := 'o restaurante';
  v_refund_percent NUMERIC := 0;
  v_refund_amount NUMERIC := 0;
  v_recovery_from_restaurant NUMERIC := 0;
  v_client_before NUMERIC := 0;
  v_client_after NUMERIC := 0;
  v_restaurant_before NUMERIC := 0;
  v_restaurant_after NUMERIC := 0;
  v_message TEXT := '';
  v_cancel_count INTEGER := 0;
  v_points INTEGER := 0;
  v_is_test_user BOOLEAN := FALSE;
  v_skip_limit BOOLEAN := FALSE;
  v_is_timeout BOOLEAN := FALSE;
  v_client_entry_type TEXT := 'order_cancellation_refund';
BEGIN
  v_is_timeout := p_reason IN ('restaurant_timeout', 'system_timeout');
  v_skip_limit := v_is_timeout;
  IF v_is_timeout THEN
    v_client_entry_type := 'order_timeout_refund';
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
      AND created_at >= now() - interval '24 hours';

    IF v_cancel_count >= 999 THEN
      BEGIN
        EXECUTE 'SELECT public.register_user_fraud_event($1,$2,$3,$4,$5)'
        USING p_user_id,
          'daily_cancellation_limit_reached',
          25,
          'high',
          jsonb_build_object('cancel_count_24h', v_cancel_count);
      EXCEPTION WHEN undefined_function THEN
        NULL;
      END;
      RAISE EXCEPTION 'daily_cancellation_limit_reached';
    END IF;
  END IF;

  SELECT o.*, COALESCE(r.name, 'o restaurante') AS restaurant_name
  INTO v_order
  FROM public.orders o
  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.id = p_order_id
    AND (o.client_id = p_user_id OR o.customer_id = p_user_id)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  v_restaurant_name := COALESCE(v_order.restaurant_name, 'o restaurante');

  IF v_order.status IN ('in_transit', 'courier_assigned', 'on_the_way', 'arrived', 'delivered', 'completed') THEN
    BEGIN
      EXECUTE 'SELECT public.register_user_fraud_event($1,$2,$3,$4,$5)'
      USING p_user_id,
        'late_cancellation_attempt',
        12,
        'medium',
        jsonb_build_object('order_id', p_order_id, 'status', v_order.status);
    EXCEPTION WHEN undefined_function THEN
      NULL;
    END;
    RAISE EXCEPTION 'cancellation_not_allowed';
  END IF;

  IF v_order.status = 'cancelled' THEN
    RETURN jsonb_build_object(
      'success', true,
      'status', 'cancelled',
      'refund_percent', 0,
      'refund_amount', 0,
      'message', 'Pedido ja estava cancelado.'
    );
  END IF;

  CASE v_order.status
    WHEN 'pending' THEN
      v_refund_percent := 1.0;
      v_points := 1;
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
  INTO v_payment_split
  FROM public.payment_splits
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF v_refund_amount > 0 THEN
    SELECT *
    INTO v_client_wallet
    FROM public.wallets
    WHERE user_id = p_user_id
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'client_wallet_not_found';
    END IF;

    IF v_order.status = 'accepted' AND v_payment_split.status = 'restaurant_confirmed' THEN
      SELECT COALESCE(owner_id, user_id)
      INTO v_restaurant_owner
      FROM public.restaurants
      WHERE id = v_order.restaurant_id
      LIMIT 1;

      IF v_restaurant_owner IS NOT NULL THEN
        SELECT *
        INTO v_restaurant_wallet
        FROM public.wallets
        WHERE user_id = v_restaurant_owner
        LIMIT 1
        FOR UPDATE;

        IF FOUND THEN
          v_recovery_from_restaurant := LEAST(
            ROUND(COALESCE(v_payment_split.restaurant_amount, 0), 2),
            ROUND(COALESCE(v_restaurant_wallet.balance, 0), 2),
            v_refund_amount
          );

          IF v_recovery_from_restaurant > 0 THEN
            v_restaurant_before := COALESCE(v_restaurant_wallet.balance, 0);
            v_restaurant_after := ROUND(v_restaurant_before - v_recovery_from_restaurant, 2);

            UPDATE public.wallets
            SET balance = v_restaurant_after,
                updated_at = now()
            WHERE id = v_restaurant_wallet.id;

            INSERT INTO public.wallet_ledger (
              wallet_id, user_id, order_id, direction, entry_type, amount,
              balance_before, balance_after, metadata
            )
            VALUES (
              v_restaurant_wallet.id,
              v_restaurant_owner,
              p_order_id,
              'debit',
              'restaurant_cancellation_reversal',
              v_recovery_from_restaurant,
              v_restaurant_before,
              v_restaurant_after,
              jsonb_build_object(
                'reason', COALESCE(p_reason, 'customer_cancellation'),
                'refund_percent', v_refund_percent
              )
            );
          END IF;
        END IF;
      END IF;
    END IF;

    v_client_before := COALESCE(v_client_wallet.balance, 0);
    v_client_after := ROUND(v_client_before + v_refund_amount, 2);

    UPDATE public.wallets
    SET balance = v_client_after,
        updated_at = now()
    WHERE id = v_client_wallet.id;

    INSERT INTO public.wallet_ledger (
      wallet_id, user_id, order_id, direction, entry_type, amount,
      balance_before, balance_after, metadata
    )
    VALUES (
      v_client_wallet.id,
      p_user_id,
      p_order_id,
      'credit',
      v_client_entry_type,
      v_refund_amount,
      v_client_before,
      v_client_after,
      jsonb_build_object(
        'reason', COALESCE(p_reason, 'customer_cancellation'),
        'refund_percent', v_refund_percent,
        'recovered_from_restaurant', v_recovery_from_restaurant
      )
    );
  END IF;

  UPDATE public.orders
  SET status = 'cancelled',
      updated_at = now()
  WHERE id = p_order_id;

  IF FOUND AND v_payment_split.order_id IS NOT NULL THEN
    UPDATE public.payment_splits
    SET status = 'cancelled',
        escrow_amount = GREATEST(COALESCE(escrow_amount, 0) - v_refund_amount, 0),
        settled_at = now()
    WHERE order_id = p_order_id;
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
      'recovered_from_restaurant', v_recovery_from_restaurant
    )
  );

  IF v_is_timeout THEN
    BEGIN
      PERFORM public.create_app_notification(
        p_user_id := p_user_id,
        p_type := 'REFUND_COMPLETED',
        p_title := 'Pedido nao confirmado a tempo',
        p_body := 'O restaurante ' || v_restaurant_name || ' nao confirmou o pedido. O valor voltou para a sua conta.',
        p_action := 'OPEN_WALLET',
        p_entity_id := p_order_id::text,
        p_priority := 'HIGH',
        p_channel := 'wallet',
        p_metadata := jsonb_build_object(
          'order_id', p_order_id,
          'reason', p_reason,
          'amount', v_refund_amount,
          'restaurant_name', v_restaurant_name
        )
      );
    EXCEPTION WHEN undefined_function THEN
      NULL;
    END;
  END IF;

  BEGIN
    EXECUTE 'SELECT public.register_user_fraud_event($1,$2,$3,$4,$5)'
    USING p_user_id,
      'order_cancelled_by_customer',
      v_points,
      CASE
        WHEN v_points >= 10 THEN 'high'
        WHEN v_points >= 5 THEN 'medium'
        ELSE 'low'
      END,
      jsonb_build_object(
        'order_id', p_order_id,
        'status', v_order.status,
        'refund_percent', ROUND(v_refund_percent * 100, 2),
        'refund_amount', v_refund_amount
      );
  EXCEPTION WHEN undefined_function THEN
    NULL;
  END;

  IF v_order.status = 'pending' OR v_order.status = 'paid' THEN
    v_message := 'Pedido cancelado com reembolso total.';
  ELSIF v_order.status = 'accepted' THEN
    v_message := 'Pedido cancelado com reembolso parcial de 80%.';
  ELSIF v_order.status = 'preparing' THEN
    v_message := 'Pedido cancelado sem reembolso porque ja estava em preparacao.';
  ELSE
    v_message := 'Pedido cancelado.';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', 'cancelled',
    'refund_percent', ROUND(v_refund_percent * 100, 2),
    'refund_amount', v_refund_amount,
    'message', v_message
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.process_order_cancellation(UUID, UUID, TEXT) TO authenticated, service_role;
