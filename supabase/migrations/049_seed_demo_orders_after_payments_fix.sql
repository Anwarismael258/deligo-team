BEGIN;
DO $$
DECLARE
  v_restaurant_owner_id UUID;
  v_client_id UUID;
  v_courier_id UUID;
  v_restaurant_id UUID;
  v_burger UUID;
  v_combo UUID;
  v_matapa UUID;
  v_wrap UUID;
  v_drink UUID;
  v_order_active UUID := '49000000-0000-0000-0000-000000000001';
  v_order_ready UUID := '49000000-0000-0000-0000-000000000002';
  v_order_late UUID := '49000000-0000-0000-0000-000000000003';
  v_order_cancelled UUID := '49000000-0000-0000-0000-000000000004';
  v_order_reviewed UUID := '49000000-0000-0000-0000-000000000005';
BEGIN
  SELECT id INTO v_restaurant_owner_id FROM auth.users WHERE email = 'anis.justwork@gmail.com' LIMIT 1;
  SELECT id INTO v_client_id FROM auth.users WHERE email = 'anwarismael258@gmail.com' LIMIT 1;
  SELECT id INTO v_courier_id FROM auth.users WHERE email = 'youngmonster199@gmail.com' LIMIT 1;

  IF v_restaurant_owner_id IS NULL OR v_client_id IS NULL OR v_courier_id IS NULL THEN
    RAISE NOTICE 'Demo order seed skipped: users not found.';
    RETURN;
  END IF;

  SELECT id INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_restaurant_owner_id
  ORDER BY COALESCE(created_at, NOW()) ASC
  LIMIT 1;

  IF v_restaurant_id IS NULL THEN
    RAISE NOTICE 'Demo order seed skipped: restaurant not found.';
    RETURN;
  END IF;

  SELECT id INTO v_combo FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Combo Almoco Deligo' LIMIT 1;
  SELECT id INTO v_burger FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Burger Deligo' LIMIT 1;
  SELECT id INTO v_matapa FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Matapa Premium' LIMIT 1;
  SELECT id INTO v_wrap FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Wrap Light de Frango' LIMIT 1;
  SELECT id INTO v_drink FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Coca-Cola 2L' LIMIT 1;

  BEGIN
    DELETE FROM public.messages WHERE order_id IN (v_order_active, v_order_ready, v_order_late, v_order_cancelled, v_order_reviewed);
    DELETE FROM public.reviews WHERE order_id IN (v_order_active, v_order_ready, v_order_late, v_order_cancelled, v_order_reviewed);
    DELETE FROM public.payments WHERE order_id IN (v_order_active, v_order_ready, v_order_late, v_order_cancelled, v_order_reviewed);
    DELETE FROM public.deliveries WHERE order_id IN (v_order_active, v_order_ready, v_order_late, v_order_cancelled, v_order_reviewed);
    DELETE FROM public.order_items WHERE order_id IN (v_order_active, v_order_ready, v_order_late, v_order_cancelled, v_order_reviewed);
    DELETE FROM public.orders WHERE id IN (v_order_active, v_order_ready, v_order_late, v_order_cancelled, v_order_reviewed);

    INSERT INTO public.orders (
      id, client_id, customer_id, restaurant_id, courier_id, status, total_amount, total,
      payment_status, delivery_fee, admin_commission, delivery_address, delivery_latitude,
      delivery_longitude, confirmed_by_customer, created_at, updated_at
    )
    VALUES
      (v_order_active, v_client_id, v_client_id, v_restaurant_id, v_courier_id, 'in_transit', 1100, 1100, 'completed', 100, 165, 'Av. Julius Nyerere, Maputo', -25.9653, 32.5891, FALSE, NOW() - interval '35 minutes', NOW() - interval '2 minutes'),
      (v_order_ready, v_client_id, v_client_id, v_restaurant_id, NULL, 'ready', 850, 850, 'completed', 100, 127.5, 'Av. Julius Nyerere, Maputo', -25.9653, 32.5891, FALSE, NOW() - interval '18 minutes', NOW() - interval '5 minutes'),
      (v_order_late, v_client_id, v_client_id, v_restaurant_id, NULL, 'preparing', 990, 990, 'completed', 120, 148.5, 'Av. Julius Nyerere, Maputo', -25.9653, 32.5891, FALSE, NOW() - interval '95 minutes', NOW() - interval '40 minutes'),
      (v_order_cancelled, v_client_id, v_client_id, v_restaurant_id, NULL, 'cancelled', 540, 540, 'failed', 0, 81, 'Retirada no restaurante', NULL, NULL, FALSE, NOW() - interval '2 hours', NOW() - interval '110 minutes'),
      (v_order_reviewed, v_client_id, v_client_id, v_restaurant_id, v_courier_id, 'delivered', 1340, 1340, 'completed', 150, 201, 'Av. Julius Nyerere, Maputo', -25.9653, 32.5891, TRUE, NOW() - interval '1 day', NOW() - interval '23 hours');

    INSERT INTO public.order_items (id, order_id, menu_item_id, quantity, price, unit_price, subtotal, created_at)
    VALUES
      (gen_random_uuid(), v_order_active, v_burger, 2, 500, 500, 1000, NOW() - interval '35 minutes'),
      (gen_random_uuid(), v_order_ready, v_combo, 1, 750, 750, 750, NOW() - interval '18 minutes'),
      (gen_random_uuid(), v_order_late, v_matapa, 1, 870, 870, 870, NOW() - interval '95 minutes'),
      (gen_random_uuid(), v_order_cancelled, v_wrap, 1, 390, 390, 390, NOW() - interval '2 hours'),
      (gen_random_uuid(), v_order_reviewed, v_burger, 2, 480, 480, 960, NOW() - interval '1 day'),
      (gen_random_uuid(), v_order_reviewed, v_drink, 1, 180, 180, 180, NOW() - interval '1 day');

    INSERT INTO public.payments (id, order_id, amount, payment_ref, payment_method, status, transaction_id, created_at, updated_at)
    VALUES
      (gen_random_uuid(), v_order_active, 1100, 'PAY-DELIGO-ACTIVE', 'wallet', 'completed', 'PAY-DELIGO-ACTIVE', NOW() - interval '34 minutes', NOW() - interval '33 minutes'),
      (gen_random_uuid(), v_order_ready, 850, 'PAY-DELIGO-READY', 'wallet', 'completed', 'PAY-DELIGO-READY', NOW() - interval '17 minutes', NOW() - interval '16 minutes'),
      (gen_random_uuid(), v_order_late, 990, 'PAY-DELIGO-LATE', 'wallet', 'completed', 'PAY-DELIGO-LATE', NOW() - interval '94 minutes', NOW() - interval '93 minutes'),
      (gen_random_uuid(), v_order_cancelled, 540, 'PAY-DELIGO-CANCELLED', 'wallet', 'failed', 'PAY-DELIGO-CANCELLED', NOW() - interval '2 hours', NOW() - interval '111 minutes'),
      (gen_random_uuid(), v_order_reviewed, 1340, 'PAY-DELIGO-REVIEW', 'wallet', 'completed', 'PAY-DELIGO-REVIEW', NOW() - interval '1 day', NOW() - interval '1 day');

    INSERT INTO public.messages (id, order_id, sender_id, sender_name, sender_role, text, created_at)
    VALUES
      (gen_random_uuid(), v_order_reviewed, v_client_id, 'Anwar Ismael', 'client', 'Meu portao e azul, pode tocar quando chegar.', NOW() - interval '1 day' + interval '10 minutes'),
      (gen_random_uuid(), v_order_reviewed, v_restaurant_owner_id, 'Deligo Restaurante', 'restaurant', 'Pedido confirmado, estamos a preparar.', NOW() - interval '1 day' + interval '14 minutes'),
      (gen_random_uuid(), v_order_reviewed, v_courier_id, 'Deligo Biker', 'courier', 'Estou a caminho do restaurante.', NOW() - interval '1 day' + interval '22 minutes'),
      (gen_random_uuid(), v_order_active, v_courier_id, 'Deligo Biker', 'courier', 'Pedido em andamento, chego em breve.', NOW() - interval '9 minutes');

    INSERT INTO public.deliveries (id, order_id, courier_id, pickup_latitude, pickup_longitude, delivery_latitude, delivery_longitude, current_latitude, current_longitude, status, created_at, updated_at)
    VALUES
      (gen_random_uuid(), v_order_active, v_courier_id, -25.9645, 32.5880, -25.9653, 32.5891, -25.9649, 32.5887, 'in_transit', NOW() - interval '35 minutes', NOW() - interval '2 minutes')
    ON CONFLICT DO NOTHING;

    INSERT INTO public.reviews (id, order_id, reviewer_id, rating, comment, created_at)
    VALUES
      (gen_random_uuid(), v_order_reviewed, v_client_id, 5, 'Entrega rapida e comida excelente.', NOW() - interval '22 hours');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE NOTICE 'Demo order seed skipped after payments fix: %', SQLERRM;
  END;
END $$;
COMMIT;
