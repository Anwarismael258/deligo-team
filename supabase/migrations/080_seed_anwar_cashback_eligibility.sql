BEGIN;
DO $$
DECLARE
  v_client_id UUID := '680a7827-68fe-49fa-b005-62e148a6e2b4';
  v_restaurant_owner_id UUID := 'feadf74b-2d43-4e65-ab13-afc02e5837a4';
  v_platform_user_id UUID := '2ef7f269-b36e-4903-ab2d-72b2a74ca28e';
  v_restaurant_id UUID;
  v_menu_item_id UUID;
  v_platform_wallet_id UUID;
  v_existing_platform_balance NUMERIC := 0;
  v_platform_target_balance NUMERIC := 15000;
  v_order_ids UUID[] := ARRAY[
    '80000000-0000-0000-0000-000000000001'::UUID,
    '80000000-0000-0000-0000-000000000002'::UUID,
    '80000000-0000-0000-0000-000000000003'::UUID,
    '80000000-0000-0000-0000-000000000004'::UUID,
    '80000000-0000-0000-0000-000000000005'::UUID,
    '80000000-0000-0000-0000-000000000006'::UUID,
    '80000000-0000-0000-0000-000000000007'::UUID,
    '80000000-0000-0000-0000-000000000008'::UUID
  ];
  v_order_id UUID;
  v_index INTEGER := 0;
  v_food_total NUMERIC := 860;
  v_delivery_fee NUMERIC := 140;
  v_order_total NUMERIC := 1000;
  v_payment_ref TEXT;
BEGIN
  SELECT id
  INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_restaurant_owner_id
  ORDER BY created_at NULLS LAST, id
  LIMIT 1;

  IF v_restaurant_id IS NULL THEN
    RAISE NOTICE 'Cashback seed skipped: restaurant not found for owner %', v_restaurant_owner_id;
    RETURN;
  END IF;

  SELECT id
  INTO v_menu_item_id
  FROM public.menu_items
  WHERE restaurant_id = v_restaurant_id
  ORDER BY created_at NULLS LAST, id
  LIMIT 1;

  INSERT INTO public.wallets (user_id, balance, currency, is_active, created_at, updated_at)
  VALUES (v_platform_user_id, 0, 'MZN', TRUE, NOW(), NOW())
  ON CONFLICT (user_id) DO NOTHING;

  SELECT id, COALESCE(balance, 0)
  INTO v_platform_wallet_id, v_existing_platform_balance
  FROM public.wallets
  WHERE user_id = v_platform_user_id
  LIMIT 1;

  IF v_platform_wallet_id IS NOT NULL AND v_existing_platform_balance < v_platform_target_balance THEN
    PERFORM public.apply_wallet_ledger_entry(
      p_wallet_id := v_platform_wallet_id,
      p_user_id := v_platform_user_id,
      p_order_id := NULL,
      p_direction := 'credit',
      p_entry_type := 'platform_reserve_topup',
      p_amount := ROUND((v_platform_target_balance - v_existing_platform_balance)::numeric, 2),
      p_reference_key := 'platform-reserve-topup-cashback-seed-20260321',
      p_metadata := jsonb_build_object(
        'source', 'cashback_seed',
        'reason', 'seed_anwar_cashback_eligibility'
      ),
      p_status := 'confirmed'
    );
  END IF;

  FOREACH v_order_id IN ARRAY v_order_ids
  LOOP
    v_index := v_index + 1;
    v_payment_ref := 'CASHBACK-SEED-' || LPAD(v_index::TEXT, 2, '0');

    DELETE FROM public.reviews WHERE order_id = v_order_id;
    DELETE FROM public.payments WHERE order_id = v_order_id;
    DELETE FROM public.payment_splits WHERE order_id = v_order_id;
    DELETE FROM public.order_items WHERE order_id = v_order_id;

    INSERT INTO public.orders (
      id,
      client_id,
      customer_id,
      restaurant_id,
      courier_id,
      status,
      total_amount,
      total,
      payment_status,
      delivery_fee,
      admin_commission,
      delivery_address,
      delivery_latitude,
      delivery_longitude,
      confirmed_by_customer,
      created_at,
      updated_at
    )
    VALUES (
      v_order_id,
      v_client_id,
      v_client_id,
      v_restaurant_id,
      NULL,
      'delivered',
      v_order_total,
      v_order_total,
      'completed',
      v_delivery_fee,
      ROUND((v_order_total * 0.06)::numeric, 2),
      'Bairro Coop, Maputo',
      -25.9653,
      32.5891,
      TRUE,
      NOW() - ((18 - v_index) || ' days')::interval,
      NOW() - ((18 - v_index) || ' days')::interval
    )
    ON CONFLICT (id) DO UPDATE
    SET client_id = EXCLUDED.client_id,
        customer_id = EXCLUDED.customer_id,
        restaurant_id = EXCLUDED.restaurant_id,
        status = 'delivered',
        total_amount = EXCLUDED.total_amount,
        total = EXCLUDED.total,
        payment_status = 'completed',
        delivery_fee = EXCLUDED.delivery_fee,
        confirmed_by_customer = TRUE,
        updated_at = NOW();

    IF v_menu_item_id IS NOT NULL THEN
      INSERT INTO public.order_items (
        id,
        order_id,
        menu_item_id,
        quantity,
        price,
        unit_price,
        subtotal,
        created_at
      )
      VALUES (
        gen_random_uuid(),
        v_order_id,
        v_menu_item_id,
        2,
        v_food_total / 2,
        v_food_total / 2,
        v_food_total,
        NOW() - ((18 - v_index) || ' days')::interval
      )
      ON CONFLICT DO NOTHING;
    END IF;

    INSERT INTO public.payments (
      id,
      order_id,
      amount,
      provider,
      payment_ref,
      payment_method,
      status,
      transaction_id,
      gateway_fee,
      created_at,
      updated_at
    )
    VALUES (
      gen_random_uuid(),
      v_order_id,
      v_order_total,
      'internal_wallet',
      v_payment_ref,
      'wallet',
      'completed',
      v_payment_ref,
      0,
      NOW() - ((18 - v_index) || ' days')::interval,
      NOW() - ((18 - v_index) || ' days')::interval
    );

    INSERT INTO public.payment_splits (
      id,
      order_id,
      total_amount,
      platform_fee,
      restaurant_amount,
      courier_amount,
      escrow_amount,
      gateway_fee,
      restaurant_fee_percent,
      courier_fee_percent,
      restaurant_platform_fee,
      courier_platform_fee,
      status,
      settled_at,
      created_at
    )
    VALUES (
      gen_random_uuid(),
      v_order_id,
      v_order_total,
      ROUND((v_food_total * 0.06 + v_delivery_fee * 0.05)::numeric, 2),
      ROUND((v_food_total * 0.94)::numeric, 2),
      ROUND((v_delivery_fee * 0.95)::numeric, 2),
      0,
      0,
      0.06,
      0.05,
      ROUND((v_food_total * 0.06)::numeric, 2),
      ROUND((v_delivery_fee * 0.05)::numeric, 2),
      'completed',
      NOW() - ((18 - v_index) || ' days')::interval,
      NOW() - ((18 - v_index) || ' days')::interval
    );

    INSERT INTO public.reviews (
      id,
      order_id,
      reviewer_id,
      rating,
      comment,
      created_at
    )
    VALUES (
      gen_random_uuid(),
      v_order_id,
      v_client_id,
      CASE WHEN v_index % 3 = 0 THEN 4 ELSE 5 END,
      CASE
        WHEN v_index % 3 = 0 THEN 'Pedido entregue com boa qualidade e dentro do prazo.'
        ELSE 'Experiencia muito boa. Entrega rapida e comida excelente.'
      END,
      NOW() - ((18 - v_index) || ' days')::interval
    );
  END LOOP;
END $$;
COMMIT;
