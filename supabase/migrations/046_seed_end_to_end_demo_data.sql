-- End-to-end demo seed for client, restaurant and courier dashboards.

ALTER TABLE IF EXISTS public.restaurants
  ADD COLUMN IF NOT EXISTS wallet_balance NUMERIC DEFAULT 0;
DO $$
DECLARE
  v_restaurant_owner_id UUID;
  v_client_id UUID;
  v_courier_id UUID;
  v_restaurant_id UUID;
  v_menu_promo UUID;
  v_menu_main UUID;
  v_menu_fast UUID;
  v_menu_side UUID;
  v_menu_drink UUID;
  v_menu_dessert UUID;
  v_menu_breakfast UUID;
  v_menu_light UUID;
  v_menu_special UUID;
  v_order_chat UUID := '46000000-0000-0000-0000-000000000001';
  v_order_d2 UUID := '46000000-0000-0000-0000-000000000002';
  v_order_d3 UUID := '46000000-0000-0000-0000-000000000003';
  v_order_d4 UUID := '46000000-0000-0000-0000-000000000004';
  v_order_d5 UUID := '46000000-0000-0000-0000-000000000005';
  v_order_d6 UUID := '46000000-0000-0000-0000-000000000006';
  v_order_today_1 UUID := '46000000-0000-0000-0000-000000000007';
  v_order_today_2 UUID := '46000000-0000-0000-0000-000000000008';
  v_order_today_3 UUID := '46000000-0000-0000-0000-000000000009';
  v_order_today_4 UUID := '46000000-0000-0000-0000-000000000010';
  v_order_today_5 UUID := '46000000-0000-0000-0000-000000000011';
  v_order_today_6 UUID := '46000000-0000-0000-0000-000000000012';
  v_order_active UUID := '46000000-0000-0000-0000-000000000013';
  v_order_ready UUID := '46000000-0000-0000-0000-000000000014';
  v_order_late_1 UUID := '46000000-0000-0000-0000-000000000015';
  v_order_late_2 UUID := '46000000-0000-0000-0000-000000000016';
  v_order_late_3 UUID := '46000000-0000-0000-0000-000000000017';
  v_demo_order_ids UUID[];
BEGIN
  SELECT id INTO v_restaurant_owner_id FROM auth.users WHERE email = 'anis.justwork@gmail.com' LIMIT 1;
  SELECT id INTO v_client_id FROM auth.users WHERE email = 'anwarismael258@gmail.com' LIMIT 1;
  SELECT id INTO v_courier_id FROM auth.users WHERE email = 'youngmonster199@gmail.com' LIMIT 1;

  IF v_restaurant_owner_id IS NULL OR v_client_id IS NULL OR v_courier_id IS NULL THEN
    RAISE NOTICE 'Seed skipped: one or more target users do not exist.';
    RETURN;
  END IF;

  SELECT id INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_restaurant_owner_id
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_restaurant_id IS NULL THEN
    RAISE NOTICE 'Seed skipped: restaurant row does not exist for anis.justwork@gmail.com.';
    RETURN;
  END IF;

  BEGIN
    UPDATE public.profiles
    SET
      full_name = COALESCE(NULLIF(full_name, ''), 'Anwar Ismael'),
      phone = COALESCE(NULLIF(phone, ''), '+258877688695'),
      role = COALESCE(NULLIF(role, ''), 'client'),
      preferred_payment_method = COALESCE(NULLIF(preferred_payment_method, ''), 'emola'),
      payment_contact = COALESCE(NULLIF(payment_contact, ''), '877688695'),
      mobile_operator = COALESCE(NULLIF(mobile_operator, ''), 'movitel'),
      address = COALESCE(NULLIF(address, ''), 'Av. Julius Nyerere, Maputo'),
      neighborhood = COALESCE(NULLIF(neighborhood, ''), 'Polana'),
      city = COALESCE(NULLIF(city, ''), 'Maputo'),
      updated_at = NOW()
    WHERE id = v_client_id OR user_id = v_client_id;

    UPDATE public.profiles
    SET
      full_name = COALESCE(NULLIF(full_name, ''), 'Deligo Biker'),
      phone = COALESCE(NULLIF(phone, ''), '+258841130015'),
      role = COALESCE(NULLIF(role, ''), 'courier'),
      kyc_status = COALESCE(NULLIF(kyc_status, ''), 'approved'),
      preferred_payment_method = COALESCE(NULLIF(preferred_payment_method, ''), 'm-pesa'),
      payment_contact = COALESCE(NULLIF(payment_contact, ''), '841130015'),
      mobile_operator = COALESCE(NULLIF(mobile_operator, ''), 'vodacom'),
      updated_at = NOW()
    WHERE id = v_courier_id OR user_id = v_courier_id;

    UPDATE public.profiles
    SET
      full_name = COALESCE(NULLIF(full_name, ''), 'Deligo Restaurante'),
      phone = COALESCE(NULLIF(phone, ''), '+258851709807'),
      role = COALESCE(NULLIF(role, ''), 'restaurant'),
      preferred_payment_method = COALESCE(NULLIF(preferred_payment_method, ''), 'm-pesa'),
      payment_contact = COALESCE(NULLIF(payment_contact, ''), '851709807'),
      mobile_operator = COALESCE(NULLIF(mobile_operator, ''), 'vodacom'),
      updated_at = NOW()
    WHERE id = v_restaurant_owner_id OR user_id = v_restaurant_owner_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Profiles seed skipped: %', SQLERRM;
  END;

  BEGIN
    INSERT INTO public.user_addresses (user_id, label, address, reference, delivery_instructions, is_default, created_at, updated_at)
    SELECT v_client_id, 'Casa', 'Av. Julius Nyerere, Maputo', 'Portao azul', 'Tocar campainha e confirmar apartamento 203', TRUE, NOW(), NOW()
    WHERE NOT EXISTS (
      SELECT 1 FROM public.user_addresses WHERE user_id = v_client_id AND is_default = TRUE
    );

    UPDATE public.user_addresses
    SET
      label = 'Casa',
      address = 'Av. Julius Nyerere, Maputo',
      reference = 'Portao azul',
      delivery_instructions = 'Tocar campainha e confirmar apartamento 203',
      is_default = TRUE,
      latitude = COALESCE(latitude, -25.9653),
      longitude = COALESCE(longitude, 32.5891),
      neighborhood = COALESCE(NULLIF(neighborhood, ''), 'Polana'),
      city = COALESCE(NULLIF(city, ''), 'Maputo'),
      updated_at = NOW()
    WHERE user_id = v_client_id AND is_default = TRUE;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Address seed skipped: %', SQLERRM;
  END;

  BEGIN
    UPDATE public.restaurants
    SET
      name = 'Deligo Restaurante',
      description = 'Restaurante urbano com pratos principais, fast food, bebidas, sobremesas e combos fortes para Maputo.',
      phone = '+258851709807',
      address = 'Av. Julius Nyerere, Maputo',
      neighborhood = 'Polana',
      city = 'Maputo',
      latitude = COALESCE(latitude, -25.9645),
      longitude = COALESCE(longitude, 32.5880),
      image_url = COALESCE(NULLIF(image_url, ''), 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80'),
      rating = 4.8,
      is_open = TRUE,
      opening_time = COALESCE(NULLIF(opening_time, ''), '08:00'),
      closing_time = COALESCE(NULLIF(closing_time, ''), '23:00'),
      estimated_delivery_time = COALESCE(estimated_delivery_time, 25),
      wallet_balance = 18450,
      updated_at = NOW()
    WHERE id = v_restaurant_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Restaurant seed skipped: %', SQLERRM;
  END;

  BEGIN
    UPDATE public.wallets SET balance = 1250, currency = 'MZN', updated_at = NOW() WHERE user_id = v_client_id;
    IF NOT FOUND THEN
      INSERT INTO public.wallets (user_id, balance, currency, created_at, updated_at)
      VALUES (v_client_id, 1250, 'MZN', NOW(), NOW());
    END IF;

    UPDATE public.wallets SET balance = 2350, currency = 'MZN', updated_at = NOW() WHERE user_id = v_courier_id;
    IF NOT FOUND THEN
      INSERT INTO public.wallets (user_id, balance, currency, created_at, updated_at)
      VALUES (v_courier_id, 2350, 'MZN', NOW(), NOW());
    END IF;

    UPDATE public.wallets SET balance = 18450, currency = 'MZN', updated_at = NOW() WHERE user_id = v_restaurant_owner_id;
    IF NOT FOUND THEN
      INSERT INTO public.wallets (user_id, balance, currency, created_at, updated_at)
      VALUES (v_restaurant_owner_id, 18450, 'MZN', NOW(), NOW());
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Wallet seed skipped: %', SQLERRM;
  END;

  BEGIN
    INSERT INTO public.menu_items (restaurant_id, name, description, price, image_url, category, is_available, created_at)
    SELECT v_restaurant_id, seeded.name, seeded.description, seeded.price, seeded.image_url, seeded.category, seeded.is_available, NOW()
    FROM (
      VALUES
        ('Combo Almoco Deligo', 'Combo promocional com burger, batata e bebida.', 650, 'https://images.unsplash.com/photo-1561758033-d89a9ad46330?auto=format&fit=crop&w=1200&q=80', 'Promocoes', TRUE),
        ('Frango Grelhado Executivo', 'Frango grelhado com arroz e salada fresca.', 780, 'https://images.unsplash.com/photo-1604908176997-125f25cc6f3d?auto=format&fit=crop&w=1200&q=80', 'Pratos principais', TRUE),
        ('Burger Deligo', 'Burger artesanal com queijo, bacon e molho da casa.', 480, 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=1200&q=80', 'Fast Food', TRUE),
        ('Batata Rustica Crocante', 'Batata rustica com ervas e molho especial.', 220, 'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?auto=format&fit=crop&w=1200&q=80', 'Acompanhamentos', FALSE),
        ('Coca-Cola 2L', 'Refrigerante gelado para acompanhar o pedido.', 180, 'https://images.unsplash.com/photo-1629203851122-3726ecdf080e?auto=format&fit=crop&w=1200&q=80', 'Bebidas', FALSE),
        ('Cheesecake de Morango', 'Sobremesa cremosa com cobertura de morango.', 260, 'https://images.unsplash.com/photo-1533134242443-d4fd215305ad?auto=format&fit=crop&w=1200&q=80', 'Sobremesas', FALSE),
        ('Tosta Mista da Casa', 'Lanche rapido com queijo e fiambre.', 190, 'https://images.unsplash.com/photo-1528735602780-2552fd46c7af?auto=format&fit=crop&w=1200&q=80', 'Pequeno-almoco / Lanches', FALSE),
        ('Wrap Light de Frango', 'Wrap leve com legumes crocantes e molho de iogurte.', 390, 'https://images.unsplash.com/photo-1608039755401-742074f0548d?auto=format&fit=crop&w=1200&q=80', 'Saudavel / Light', TRUE),
        ('Matapa Premium', 'Especialidade local servida com arroz aromatizado.', 860, 'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=1200&q=80', 'Especialidades', TRUE),
        ('Pizza Mozzarella Suprema', 'Pizza media com mozzarella e manjericao.', 690, 'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=1200&q=80', 'Fast Food', FALSE)
    ) AS seeded(name, description, price, image_url, category, is_available)
    WHERE NOT EXISTS (
      SELECT 1 FROM public.menu_items mi WHERE mi.restaurant_id = v_restaurant_id AND mi.name = seeded.name
    );

    UPDATE public.menu_items SET category = 'Promocoes', is_available = TRUE WHERE restaurant_id = v_restaurant_id AND name = 'Combo Almoco Deligo';
    UPDATE public.menu_items SET category = 'Pratos principais', is_available = TRUE WHERE restaurant_id = v_restaurant_id AND name = 'Frango Grelhado Executivo';
    UPDATE public.menu_items SET category = 'Fast Food', is_available = TRUE WHERE restaurant_id = v_restaurant_id AND name = 'Burger Deligo';
    UPDATE public.menu_items SET category = 'Acompanhamentos', is_available = FALSE WHERE restaurant_id = v_restaurant_id AND name = 'Batata Rustica Crocante';
    UPDATE public.menu_items SET category = 'Bebidas', is_available = FALSE WHERE restaurant_id = v_restaurant_id AND name = 'Coca-Cola 2L';
    UPDATE public.menu_items SET category = 'Sobremesas', is_available = FALSE WHERE restaurant_id = v_restaurant_id AND name = 'Cheesecake de Morango';
    UPDATE public.menu_items SET category = 'Pequeno-almoco / Lanches', is_available = FALSE WHERE restaurant_id = v_restaurant_id AND name = 'Tosta Mista da Casa';
    UPDATE public.menu_items SET category = 'Saudavel / Light', is_available = TRUE WHERE restaurant_id = v_restaurant_id AND name = 'Wrap Light de Frango';
    UPDATE public.menu_items SET category = 'Especialidades', is_available = TRUE WHERE restaurant_id = v_restaurant_id AND name = 'Matapa Premium';
    UPDATE public.menu_items SET category = 'Fast Food', is_available = FALSE WHERE restaurant_id = v_restaurant_id AND name = 'Pizza Mozzarella Suprema';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Menu seed skipped: %', SQLERRM;
  END;

  SELECT id INTO v_menu_promo FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Combo Almoco Deligo' LIMIT 1;
  SELECT id INTO v_menu_main FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Frango Grelhado Executivo' LIMIT 1;
  SELECT id INTO v_menu_fast FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Burger Deligo' LIMIT 1;
  SELECT id INTO v_menu_side FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Batata Rustica Crocante' LIMIT 1;
  SELECT id INTO v_menu_drink FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Coca-Cola 2L' LIMIT 1;
  SELECT id INTO v_menu_dessert FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Cheesecake de Morango' LIMIT 1;
  SELECT id INTO v_menu_breakfast FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Tosta Mista da Casa' LIMIT 1;
  SELECT id INTO v_menu_light FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Wrap Light de Frango' LIMIT 1;
  SELECT id INTO v_menu_special FROM public.menu_items WHERE restaurant_id = v_restaurant_id AND name = 'Matapa Premium' LIMIT 1;

  v_demo_order_ids := ARRAY[
    v_order_chat, v_order_d2, v_order_d3, v_order_d4, v_order_d5, v_order_d6,
    v_order_today_1, v_order_today_2, v_order_today_3, v_order_today_4, v_order_today_5, v_order_today_6,
    v_order_active, v_order_ready, v_order_late_1, v_order_late_2, v_order_late_3
  ];

  BEGIN
    DELETE FROM public.messages WHERE order_id = ANY(v_demo_order_ids);
    DELETE FROM public.reviews WHERE order_id = ANY(v_demo_order_ids);
    DELETE FROM public.payments WHERE order_id = ANY(v_demo_order_ids);
    DELETE FROM public.deliveries WHERE order_id = ANY(v_demo_order_ids);
    DELETE FROM public.order_items WHERE order_id = ANY(v_demo_order_ids);
    DELETE FROM public.orders WHERE id = ANY(v_demo_order_ids);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Previous demo cleanup skipped: %', SQLERRM;
  END;

  BEGIN
    INSERT INTO public.orders (id, client_id, restaurant_id, courier_id, status, total_amount, delivery_fee, delivery_address, delivery_latitude, delivery_longitude, created_at, updated_at)
    VALUES
      (v_order_chat, v_client_id, v_restaurant_id, v_courier_id, 'delivered', 12500, 100, 'Demo Deligo Casa - dia 1', -25.9653, 32.5891, date_trunc('day', NOW()) - interval '6 days' + interval '12 hour 30 min', date_trunc('day', NOW()) - interval '6 days' + interval '13 hour 5 min'),
      (v_order_d2, v_client_id, v_restaurant_id, v_courier_id, 'delivered', 15200, 120, 'Demo Deligo Casa - dia 2', -25.9653, 32.5891, date_trunc('day', NOW()) - interval '5 days' + interval '13 hour 10 min', date_trunc('day', NOW()) - interval '5 days' + interval '13 hour 55 min'),
      (v_order_d3, v_client_id, v_restaurant_id, v_courier_id, 'delivered', 13800, 130, 'Demo Deligo Casa - dia 3', -25.9653, 32.5891, date_trunc('day', NOW()) - interval '4 days' + interval '14 hour 20 min', date_trunc('day', NOW()) - interval '4 days' + interval '15 hour 10 min'),
      (v_order_d4, v_client_id, v_restaurant_id, v_courier_id, 'delivered', 17600, 150, 'Demo Deligo Casa - dia 4', -25.9653, 32.5891, date_trunc('day', NOW()) - interval '3 days' + interval '18 hour 15 min', date_trunc('day', NOW()) - interval '3 days' + interval '19 hour 2 min'),
      (v_order_d5, v_client_id, v_restaurant_id, v_courier_id, 'delivered', 24300, 180, 'Demo Deligo Casa - dia 5', -25.9653, 32.5891, date_trunc('day', NOW()) - interval '2 days' + interval '19 hour 10 min', date_trunc('day', NOW()) - interval '2 days' + interval '20 hour 5 min'),
      (v_order_d6, v_client_id, v_restaurant_id, v_courier_id, 'delivered', 31900, 200, 'Demo Deligo Casa - dia 6', -25.9653, 32.5891, date_trunc('day', NOW()) - interval '1 day' + interval '20 hour 5 min', date_trunc('day', NOW()) - interval '1 day' + interval '21 hour 1 min'),
      (v_order_today_1, v_client_id, v_restaurant_id, v_courier_id, 'delivered', 1200, 100, 'Demo Deligo Casa - hora 08', -25.9653, 32.5891, date_trunc('day', NOW()) + interval '8 hour 15 min', date_trunc('day', NOW()) + interval '8 hour 55 min'),
      (v_order_today_2, v_client_id, v_restaurant_id, v_courier_id, 'delivered', 2500, 120, 'Demo Deligo Casa - hora 10', -25.9653, 32.5891, date_trunc('day', NOW()) + interval '10 hour 10 min', date_trunc('day', NOW()) + interval '10 hour 52 min'),
      (v_order_today_3, v_client_id, v_restaurant_id, v_courier_id, 'delivered', 9800, 150, 'Demo Deligo Casa - hora 12', -25.9653, 32.5891, date_trunc('day', NOW()) + interval '12 hour 12 min', date_trunc('day', NOW()) + interval '12 hour 59 min'),
      (v_order_today_4, v_client_id, v_restaurant_id, v_courier_id, 'delivered', 3200, 120, 'Demo Deligo Casa - hora 15', -25.9653, 32.5891, date_trunc('day', NOW()) + interval '15 hour 5 min', date_trunc('day', NOW()) + interval '15 hour 41 min'),
      (v_order_today_5, v_client_id, v_restaurant_id, v_courier_id, 'delivered', 12400, 180, 'Demo Deligo Casa - hora 19', -25.9653, 32.5891, date_trunc('day', NOW()) + interval '19 hour 2 min', date_trunc('day', NOW()) + interval '19 hour 54 min'),
      (v_order_today_6, v_client_id, v_restaurant_id, v_courier_id, 'delivered', 6700, 150, 'Demo Deligo Casa - hora 21', -25.9653, 32.5891, date_trunc('day', NOW()) + interval '21 hour 7 min', date_trunc('day', NOW()) + interval '21 hour 58 min'),
      (v_order_active, v_client_id, v_restaurant_id, v_courier_id, 'in_transit', 1100, 100, 'Demo Deligo Casa - pedido em andamento', -25.9653, 32.5891, NOW() - interval '35 min', NOW() - interval '5 min'),
      (v_order_ready, v_client_id, v_restaurant_id, NULL, 'ready', 850, 100, 'Demo Deligo Casa - pedido disponivel', -25.9640, 32.5902, NOW() - interval '10 min', NOW() - interval '2 min'),
      (v_order_late_1, v_client_id, v_restaurant_id, NULL, 'accepted', 920, 100, 'Demo Deligo Casa - atraso 1', -25.9625, 32.5910, NOW() - interval '140 min', NOW() - interval '120 min'),
      (v_order_late_2, v_client_id, v_restaurant_id, NULL, 'preparing', 1080, 120, 'Demo Deligo Casa - atraso 2', -25.9669, 32.5898, NOW() - interval '115 min', NOW() - interval '90 min'),
      (v_order_late_3, v_client_id, v_restaurant_id, NULL, 'ready', 990, 100, 'Demo Deligo Casa - atraso 3', -25.9632, 32.5875, NOW() - interval '95 min', NOW() - interval '70 min');
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Orders seed skipped: %', SQLERRM;
  END;

  BEGIN
    INSERT INTO public.order_items (order_id, menu_item_id, quantity, unit_price, subtotal, created_at)
    VALUES
      (v_order_chat, v_menu_main, 5, 2480, 12400, NOW() - interval '6 days'),
      (v_order_d2, v_menu_promo, 4, 3770, 15080, NOW() - interval '5 days'),
      (v_order_d3, v_menu_fast, 6, 2280, 13680, NOW() - interval '4 days'),
      (v_order_d4, v_menu_special, 2, 8725, 17450, NOW() - interval '3 days'),
      (v_order_d5, v_menu_main, 3, 8040, 24120, NOW() - interval '2 days'),
      (v_order_d6, v_menu_promo, 5, 6340, 31700, NOW() - interval '1 day'),
      (v_order_today_1, v_menu_breakfast, 6, 183.33, 1100, NOW()),
      (v_order_today_2, v_menu_side, 10, 238, 2380, NOW()),
      (v_order_today_3, v_menu_main, 12, 804, 9648, NOW()),
      (v_order_today_4, v_menu_light, 8, 385, 3080, NOW()),
      (v_order_today_5, v_menu_special, 14, 872, 12208, NOW()),
      (v_order_today_6, v_menu_fast, 14, 468, 6552, NOW()),
      (v_order_active, v_menu_fast, 2, 500, 1000, NOW()),
      (v_order_ready, v_menu_promo, 1, 750, 750, NOW()),
      (v_order_late_1, v_menu_drink, 4, 205, 820, NOW()),
      (v_order_late_2, v_menu_side, 4, 240, 960, NOW()),
      (v_order_late_3, v_menu_dessert, 3, 290, 870, NOW());
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Order items seed skipped: %', SQLERRM;
  END;

  BEGIN
    INSERT INTO public.payments (order_id, amount, payment_method, status, transaction_id, created_at, updated_at)
    VALUES
      (v_order_chat, 12500, 'mobile_money', 'completed', 'PAY-DEMO-001', NOW() - interval '6 days', NOW() - interval '6 days'),
      (v_order_d2, 15200, 'mobile_money', 'completed', 'PAY-DEMO-002', NOW() - interval '5 days', NOW() - interval '5 days'),
      (v_order_d3, 13800, 'mobile_money', 'completed', 'PAY-DEMO-003', NOW() - interval '4 days', NOW() - interval '4 days'),
      (v_order_d4, 17600, 'mobile_money', 'completed', 'PAY-DEMO-004', NOW() - interval '3 days', NOW() - interval '3 days'),
      (v_order_d5, 24300, 'mobile_money', 'completed', 'PAY-DEMO-005', NOW() - interval '2 days', NOW() - interval '2 days'),
      (v_order_d6, 31900, 'mobile_money', 'completed', 'PAY-DEMO-006', NOW() - interval '1 day', NOW() - interval '1 day'),
      (v_order_today_1, 1200, 'mobile_money', 'completed', 'PAY-DEMO-007', NOW(), NOW()),
      (v_order_today_2, 2500, 'mobile_money', 'completed', 'PAY-DEMO-008', NOW(), NOW()),
      (v_order_today_3, 9800, 'mobile_money', 'completed', 'PAY-DEMO-009', NOW(), NOW()),
      (v_order_today_4, 3200, 'mobile_money', 'completed', 'PAY-DEMO-010', NOW(), NOW()),
      (v_order_today_5, 12400, 'mobile_money', 'completed', 'PAY-DEMO-011', NOW(), NOW()),
      (v_order_today_6, 6700, 'mobile_money', 'completed', 'PAY-DEMO-012', NOW(), NOW()),
      (v_order_active, 1100, 'mobile_money', 'completed', 'PAY-DEMO-013', NOW(), NOW()),
      (v_order_ready, 850, 'mobile_money', 'completed', 'PAY-DEMO-014', NOW(), NOW());
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Payments seed skipped: %', SQLERRM;
  END;

  BEGIN
    INSERT INTO public.reviews (order_id, reviewer_id, rating, comment, created_at)
    VALUES
      (v_order_chat, v_client_id, 5, 'Entrega rapida e comida excelente.', NOW() - interval '5 days'),
      (v_order_d2, v_client_id, 5, 'Muito bom, quero pedir novamente.', NOW() - interval '4 days'),
      (v_order_d3, v_client_id, 2, 'A bebida chegou quente e faltou molho.', NOW() - interval '4 days'),
      (v_order_d4, v_client_id, 5, 'Estafeta simpatico e restaurante rapido.', NOW() - interval '3 days'),
      (v_order_d5, v_client_id, 2, 'Demorou mais do que eu esperava.', NOW() - interval '2 days'),
      (v_order_d6, v_client_id, 5, 'Combo muito bom e porcao generosa.', NOW() - interval '1 day');
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Reviews seed skipped: %', SQLERRM;
  END;

  BEGIN
    INSERT INTO public.messages (order_id, sender_id, sender_name, sender_role, text, created_at)
    VALUES
      (v_order_chat, v_client_id, 'Anwar Ismael', 'client', 'Meu portao e azul. Podem tocar quando chegarem.', NOW() - interval '6 days' + interval '12 hour 35 min'),
      (v_order_chat, v_restaurant_owner_id, 'Deligo Restaurante', 'restaurant', 'Pedido confirmado. Estamos a preparar agora.', NOW() - interval '6 days' + interval '12 hour 40 min'),
      (v_order_chat, v_courier_id, 'Deligo Biker', 'courier', 'Estou a caminho do restaurante e depois sigo para a entrega.', NOW() - interval '6 days' + interval '12 hour 46 min'),
      (v_order_chat, v_client_id, 'Anwar Ismael', 'client', 'Perfeito, obrigado.', NOW() - interval '6 days' + interval '12 hour 48 min');
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Messages seed skipped: %', SQLERRM;
  END;

  BEGIN
    INSERT INTO public.deliveries (order_id, courier_id, pickup_latitude, pickup_longitude, delivery_latitude, delivery_longitude, current_latitude, current_longitude, status, created_at, updated_at)
    VALUES
      (v_order_active, v_courier_id, -25.9645, 32.5880, -25.9653, 32.5891, -25.9649, 32.5887, 'in_transit', NOW() - interval '35 min', NOW() - interval '2 min');
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Delivery seed skipped: %', SQLERRM;
  END;

  BEGIN
    INSERT INTO public.favorites (user_id, restaurant_id, created_at)
    SELECT v_client_id, v_restaurant_id, NOW()
    WHERE NOT EXISTS (
      SELECT 1 FROM public.favorites WHERE user_id = v_client_id AND restaurant_id = v_restaurant_id
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Favorites seed skipped: %', SQLERRM;
  END;
END $$;
