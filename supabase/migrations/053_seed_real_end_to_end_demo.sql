BEGIN;
CREATE OR REPLACE FUNCTION public.seed_deligo_demo_order(
  p_payment_ref TEXT,
  p_client_id UUID,
  p_restaurant_id UUID,
  p_courier_id UUID,
  p_status TEXT,
  p_total_amount NUMERIC,
  p_delivery_fee NUMERIC,
  p_created_at TIMESTAMPTZ,
  p_delivery_address TEXT,
  p_delivery_latitude NUMERIC DEFAULT NULL,
  p_delivery_longitude NUMERIC DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_order_id UUID;
  v_menu_item_id UUID;
  v_food_total NUMERIC;
  v_platform_fee NUMERIC;
  v_restaurant_amount NUMERIC;
  v_courier_amount NUMERIC;
BEGIN
  SELECT order_id
  INTO v_order_id
  FROM public.payments
  WHERE payment_ref = p_payment_ref
  LIMIT 1;

  IF v_order_id IS NOT NULL THEN
    RETURN v_order_id;
  END IF;

  SELECT id
  INTO v_menu_item_id
  FROM public.menu_items
  WHERE restaurant_id = p_restaurant_id
  ORDER BY is_available DESC, created_at ASC NULLS LAST, name ASC
  LIMIT 1;

  v_order_id := gen_random_uuid();
  v_food_total := GREATEST(COALESCE(p_total_amount, 0) - COALESCE(p_delivery_fee, 0), 0);
  v_platform_fee := ROUND((v_food_total * 0.15) + (COALESCE(p_delivery_fee, 0) * 0.15), 2);
  v_restaurant_amount := ROUND(v_food_total * 0.85, 2);
  v_courier_amount := ROUND(COALESCE(p_delivery_fee, 0) * 0.85, 2);

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
    created_at,
    updated_at,
    confirmed_by_customer
  ) VALUES (
    v_order_id,
    p_client_id,
    p_client_id,
    p_restaurant_id,
    p_courier_id,
    p_status,
    p_total_amount,
    p_total_amount,
    CASE
      WHEN p_status IN ('pending', 'cancelled') THEN 'pending'
      ELSE 'completed'
    END,
    COALESCE(p_delivery_fee, 0),
    v_platform_fee,
    p_delivery_address,
    p_delivery_latitude,
    p_delivery_longitude,
    p_created_at,
    p_created_at + INTERVAL '25 minutes',
    CASE WHEN p_status IN ('delivered', 'completed') THEN TRUE ELSE FALSE END
  );

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
    ) VALUES (
      gen_random_uuid(),
      v_order_id,
      v_menu_item_id,
      1,
      p_total_amount - COALESCE(p_delivery_fee, 0),
      p_total_amount - COALESCE(p_delivery_fee, 0),
      p_total_amount - COALESCE(p_delivery_fee, 0),
      p_created_at
    );
  END IF;

  INSERT INTO public.payments (
    id,
    order_id,
    amount,
    payment_method,
    provider,
    payment_ref,
    transaction_id,
    status,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_order_id,
    p_total_amount,
    CASE
      WHEN COALESCE(p_delivery_fee, 0) > 0 THEN 'mobile_money'
      ELSE 'cash'
    END,
    'seed',
    p_payment_ref,
    p_payment_ref,
    CASE
      WHEN p_status = 'cancelled' THEN 'failed'
      WHEN p_status = 'pending' THEN 'pending'
      ELSE 'completed'
    END,
    p_created_at,
    p_created_at
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.payment_splits WHERE order_id = v_order_id
  ) THEN
    INSERT INTO public.payment_splits (
      id,
      order_id,
      total_amount,
      platform_fee,
      restaurant_amount,
      courier_amount,
      status,
      created_at
    ) VALUES (
      gen_random_uuid(),
      v_order_id,
      p_total_amount,
      v_platform_fee,
      v_restaurant_amount,
      v_courier_amount,
      CASE
        WHEN p_status IN ('delivered', 'completed', 'in_transit', 'arrived', 'ready', 'preparing', 'accepted') THEN 'completed'
        ELSE 'pending'
      END,
      p_created_at
    );
  END IF;

  IF p_courier_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.deliveries WHERE order_id = v_order_id
    ) THEN
      INSERT INTO public.deliveries (
        id,
        order_id,
        courier_id,
        pickup_latitude,
        pickup_longitude,
        delivery_latitude,
        delivery_longitude,
        current_latitude,
        current_longitude,
        status,
        created_at,
        updated_at
      )
      SELECT
        gen_random_uuid(),
        v_order_id,
        p_courier_id,
        r.latitude,
        r.longitude,
        p_delivery_latitude,
        p_delivery_longitude,
        r.latitude,
        r.longitude,
        CASE
          WHEN p_status IN ('in_transit', 'arrived') THEN 'in_transit'
          WHEN p_status IN ('delivered', 'completed') THEN 'delivered'
          ELSE 'pending'
        END,
        p_created_at,
        p_created_at
      FROM public.restaurants r
      WHERE r.id = p_restaurant_id;
    END IF;
  END IF;

  RETURN v_order_id;
END;
$$;
DO $$
DECLARE
  v_client_id UUID;
  v_restaurant_owner_id UUID;
  v_courier_id UUID;
  v_restaurant_id UUID;
  v_order_id UUID;
  v_now TIMESTAMPTZ := NOW();
  v_item RECORD;
  v_review_user_column TEXT;
BEGIN
  SELECT id INTO v_client_id
  FROM auth.users
  WHERE email = 'anwarismael258@gmail.com'
  LIMIT 1;

  SELECT id INTO v_restaurant_owner_id
  FROM auth.users
  WHERE email = 'anis.justwork@gmail.com'
  LIMIT 1;

  SELECT id INTO v_courier_id
  FROM auth.users
  WHERE email = 'youngmonster199@gmail.com'
  LIMIT 1;

  IF v_client_id IS NULL OR v_restaurant_owner_id IS NULL OR v_courier_id IS NULL THEN
    RAISE NOTICE 'Seed real end-to-end skipped: users not found.';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'reviews' AND column_name = 'reviewer_id'
  ) THEN
    v_review_user_column := 'reviewer_id';
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'reviews' AND column_name = 'user_id'
  ) THEN
    v_review_user_column := 'user_id';
  ELSE
    v_review_user_column := NULL;
  END IF;

  UPDATE public.profiles
  SET
    full_name = CASE
      WHEN id = v_client_id THEN 'Anwar Ismael'
      WHEN id = v_restaurant_owner_id THEN 'Deligo Restaurante'
      WHEN id = v_courier_id THEN 'Deligo Biker'
      ELSE full_name
    END,
    role = CASE
      WHEN id = v_client_id THEN 'client'
      WHEN id = v_restaurant_owner_id THEN 'restaurant'
      WHEN id = v_courier_id THEN 'courier'
      ELSE role
    END,
    preferred_payment_method = CASE
      WHEN id = v_client_id THEN 'emola'
      WHEN id = v_restaurant_owner_id THEN 'm-pesa'
      WHEN id = v_courier_id THEN 'm-pesa'
      ELSE preferred_payment_method
    END,
    mobile_operator = CASE
      WHEN id = v_client_id THEN 'movitel'
      ELSE 'vodacom'
    END,
    payment_contact = CASE
      WHEN id = v_client_id THEN '877688695'
      WHEN id = v_restaurant_owner_id THEN '851709807'
      WHEN id = v_courier_id THEN '841130015'
      ELSE payment_contact
    END,
    kyc_completed = CASE WHEN id = v_courier_id THEN TRUE ELSE kyc_completed END,
    kyc_status = CASE WHEN id = v_courier_id THEN 'approved' ELSE kyc_status END,
    updated_at = NOW()
  WHERE id IN (v_client_id, v_restaurant_owner_id, v_courier_id);

  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'user_addresses'
  ) THEN
    INSERT INTO public.user_addresses (
      id,
      user_id,
      label,
      address,
      reference,
      delivery_instructions,
      neighborhood,
      city,
      latitude,
      longitude,
      is_default
    )
    SELECT
      gen_random_uuid(),
      v_client_id,
      'Casa',
      'Av. Julius Nyerere, Sommerschield',
      'Portão azul',
      'Tocar antes de entrar',
      'Sommerschield',
      'Maputo',
      -25.9530,
      32.5950,
      TRUE
    WHERE NOT EXISTS (
      SELECT 1 FROM public.user_addresses
      WHERE user_id = v_client_id AND is_default = TRUE
    );
  END IF;

  INSERT INTO public.couriers (
    id,
    full_name,
    phone,
    is_online,
    vehicle_type,
    rating,
    total_deliveries,
    earnings_today,
    acceptance_rate,
    cancellation_rate,
    current_latitude,
    current_longitude,
    created_at,
    updated_at
  ) VALUES (
    v_courier_id,
    'Deligo Biker',
    '+258841130015',
    TRUE,
    'motorbike',
    4.8,
    42,
    2350,
    92,
    3,
    -25.9596,
    32.5832,
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO UPDATE
  SET
    full_name = EXCLUDED.full_name,
    phone = EXCLUDED.phone,
    is_online = EXCLUDED.is_online,
    vehicle_type = EXCLUDED.vehicle_type,
    rating = EXCLUDED.rating,
    total_deliveries = GREATEST(public.couriers.total_deliveries, EXCLUDED.total_deliveries),
    earnings_today = EXCLUDED.earnings_today,
    acceptance_rate = EXCLUDED.acceptance_rate,
    cancellation_rate = EXCLUDED.cancellation_rate,
    current_latitude = EXCLUDED.current_latitude,
    current_longitude = EXCLUDED.current_longitude,
    updated_at = NOW();

  IF EXISTS (SELECT 1 FROM public.wallets WHERE user_id = v_client_id) THEN
    UPDATE public.wallets
    SET balance = GREATEST(COALESCE(balance, 0), 4800), currency = 'MZN', is_active = TRUE, updated_at = NOW()
    WHERE user_id = v_client_id;
  ELSE
    INSERT INTO public.wallets (id, user_id, owner_id, balance, currency, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), v_client_id, v_client_id, 4800, 'MZN', TRUE, NOW(), NOW());
  END IF;

  IF EXISTS (SELECT 1 FROM public.wallets WHERE user_id = v_restaurant_owner_id) THEN
    UPDATE public.wallets
    SET balance = GREATEST(COALESCE(balance, 0), 18250), currency = 'MZN', is_active = TRUE, updated_at = NOW()
    WHERE user_id = v_restaurant_owner_id;
  ELSE
    INSERT INTO public.wallets (id, user_id, owner_id, balance, currency, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), v_restaurant_owner_id, v_restaurant_owner_id, 18250, 'MZN', TRUE, NOW(), NOW());
  END IF;

  IF EXISTS (SELECT 1 FROM public.wallets WHERE user_id = v_courier_id) THEN
    UPDATE public.wallets
    SET balance = GREATEST(COALESCE(balance, 0), 2350), currency = 'MZN', is_active = TRUE, updated_at = NOW()
    WHERE user_id = v_courier_id;
  ELSE
    INSERT INTO public.wallets (id, user_id, owner_id, balance, currency, is_active, created_at, updated_at)
    VALUES (gen_random_uuid(), v_courier_id, v_courier_id, 2350, 'MZN', TRUE, NOW(), NOW());
  END IF;

  SELECT id INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_restaurant_owner_id
  LIMIT 1;

  IF v_restaurant_id IS NULL THEN
    INSERT INTO public.restaurants (
      id,
      owner_id,
      name,
      description,
      phone,
      address,
      neighborhood,
      city,
      latitude,
      longitude,
      rating,
      is_open,
      opening_time,
      closing_time,
      estimated_delivery_time,
      wallet_balance,
      image_url,
      created_at,
      updated_at
    ) VALUES (
      gen_random_uuid(),
      v_restaurant_owner_id,
      'Deligo Restaurante',
      'Cozinha moderna moçambicana com pratos rápidos, combos e opções saudáveis.',
      '+258851709807',
      'Av. Marginal, Maputo',
      'Polana',
      'Maputo',
      -25.9608,
      32.5892,
      4.6,
      TRUE,
      '08:00',
      '23:00',
      25,
      18250,
      'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80',
      NOW(),
      NOW()
    )
    RETURNING id INTO v_restaurant_id;
  ELSE
    UPDATE public.restaurants
    SET
      name = 'Deligo Restaurante',
      description = 'Cozinha moderna moçambicana com pratos rápidos, combos e opções saudáveis.',
      phone = '+258851709807',
      address = 'Av. Marginal, Maputo',
      neighborhood = 'Polana',
      city = 'Maputo',
      latitude = -25.9608,
      longitude = 32.5892,
      rating = 4.6,
      is_open = TRUE,
      opening_time = '08:00',
      closing_time = '23:00',
      estimated_delivery_time = 25,
      wallet_balance = 18250,
      image_url = 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80',
      updated_at = NOW()
    WHERE id = v_restaurant_id;
  END IF;

  FOR v_item IN
    SELECT * FROM (
      VALUES
        ('🔥 Promoções', 'Combo Executivo', 'Prato completo com bebida e acompanhamento.', 690, TRUE, 'https://images.unsplash.com/photo-1565299624946-b28f40a0ca4b?auto=format&fit=crop&w=1200&q=80'),
        ('🥘 Pratos principais', 'Frango Grelhado', 'Frango suculento com arroz de coco.', 850, TRUE, 'https://images.unsplash.com/photo-1604908554167-9d2ea3c84a7c?auto=format&fit=crop&w=1200&q=80'),
        ('🍔 Fast Food', 'Burger Deligo', 'Hambúrguer artesanal com molho da casa.', 540, TRUE, 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=1200&q=80'),
        ('🍟 Acompanhamentos', 'Batata Especial', 'Batatas crocantes com molho picante.', 220, TRUE, 'https://images.unsplash.com/photo-1576107232684-1279f390859f?auto=format&fit=crop&w=1200&q=80'),
        ('🥤 Bebidas', 'Sumo Natural', 'Sumo fresco de manga.', 180, FALSE, 'https://images.unsplash.com/photo-1544145945-f90425340c7e?auto=format&fit=crop&w=1200&q=80'),
        ('🍰 Sobremesas', 'Cheesecake de Coco', 'Sobremesa cremosa com toque local.', 260, FALSE, 'https://images.unsplash.com/photo-1563729784474-d77dbb933a9e?auto=format&fit=crop&w=1200&q=80'),
        ('🍳 Pequeno-almoço / Lanches', 'Café Moçambicano', 'Café forte com pastel de carne.', 190, FALSE, 'https://images.unsplash.com/photo-1509042239860-f550ce710b93?auto=format&fit=crop&w=1200&q=80'),
        ('🌱 Saudável / Light', 'Bowl Fitness', 'Bowl equilibrado com legumes e frango.', 430, FALSE, 'https://images.unsplash.com/photo-1546793665-c74683f339c1?auto=format&fit=crop&w=1200&q=80'),
        ('🌍 Especialidades', 'Matapa Especial', 'Matapa cremosa com camarão.', 980, TRUE, 'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=1200&q=80'),
        ('🔥 Promoções', 'Combo Jantar', 'Hambúrguer, batata e bebida com desconto.', 720, FALSE, 'https://images.unsplash.com/photo-1550547660-d9450f859349?auto=format&fit=crop&w=1200&q=80')
    ) AS t(category, name, description, price, is_available, image_url)
  LOOP
    INSERT INTO public.menu_items (
      id,
      restaurant_id,
      name,
      description,
      price,
      image_url,
      category,
      is_available,
      created_at,
      updated_at
    )
    SELECT
      gen_random_uuid(),
      v_restaurant_id,
      v_item.name,
      v_item.description,
      v_item.price,
      v_item.image_url,
      v_item.category,
      v_item.is_available,
      NOW(),
      NOW()
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.menu_items mi
      WHERE mi.restaurant_id = v_restaurant_id
        AND mi.name = v_item.name
    );

    UPDATE public.menu_items
    SET
      description = v_item.description,
      price = v_item.price,
      image_url = v_item.image_url,
      category = v_item.category,
      is_available = v_item.is_available,
      updated_at = NOW()
    WHERE restaurant_id = v_restaurant_id
      AND name = v_item.name;
  END LOOP;

  v_order_id := public.seed_deligo_demo_order(
    'seed-demo-active',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'in_transit',
    1100,
    150,
    v_now - INTERVAL '18 minutes',
    'Av. Julius Nyerere, Sommerschield',
    -25.9530,
    32.5950
  );

  UPDATE public.deliveries
  SET
    current_latitude = -25.9560,
    current_longitude = 32.5918,
    status = 'in_transit',
    updated_at = NOW()
  WHERE order_id = v_order_id;

  INSERT INTO public.messages (id, order_id, sender_id, sender_name, sender_role, text, content, created_at)
  SELECT gen_random_uuid(), v_order_id, v_client_id, 'Anwar Ismael', 'client', 'Meu portão é azul. Pode ligar quando estiver perto?', 'Meu portão é azul. Pode ligar quando estiver perto?', NOW() - INTERVAL '16 minutes'
  WHERE NOT EXISTS (SELECT 1 FROM public.messages WHERE order_id = v_order_id AND sender_id = v_client_id);

  INSERT INTO public.messages (id, order_id, sender_id, sender_name, sender_role, text, content, created_at)
  SELECT gen_random_uuid(), v_order_id, v_restaurant_owner_id, 'Deligo Restaurante', 'restaurant', 'Pedido confirmado e em preparação.', 'Pedido confirmado e em preparação.', NOW() - INTERVAL '15 minutes'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.messages
    WHERE order_id = v_order_id AND sender_id = v_restaurant_owner_id
  );

  INSERT INTO public.messages (id, order_id, sender_id, sender_name, sender_role, text, content, created_at)
  SELECT gen_random_uuid(), v_order_id, v_courier_id, 'Deligo Biker', 'courier', 'Já estou a caminho com o pedido.', 'Já estou a caminho com o pedido.', NOW() - INTERVAL '8 minutes'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.messages
    WHERE order_id = v_order_id AND sender_id = v_courier_id
  );

  PERFORM public.seed_deligo_demo_order(
    'seed-demo-hour-08',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'delivered',
    1300,
    100,
    date_trunc('day', v_now) + INTERVAL '8 hours 30 minutes',
    'Sommerschield',
    -25.9531,
    32.5949
  );
  PERFORM public.seed_deligo_demo_order(
    'seed-demo-hour-10',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'delivered',
    2600,
    100,
    date_trunc('day', v_now) + INTERVAL '10 hours 40 minutes',
    'Sommerschield',
    -25.9531,
    32.5949
  );
  PERFORM public.seed_deligo_demo_order(
    'seed-demo-hour-12',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'delivered',
    9900,
    150,
    date_trunc('day', v_now) + INTERVAL '12 hours 20 minutes',
    'Polana',
    -25.9520,
    32.5910
  );
  PERFORM public.seed_deligo_demo_order(
    'seed-demo-hour-15',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'delivered',
    3300,
    100,
    date_trunc('day', v_now) + INTERVAL '15 hours 10 minutes',
    'Polana',
    -25.9520,
    32.5910
  );
  PERFORM public.seed_deligo_demo_order(
    'seed-demo-hour-19',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'delivered',
    12500,
    150,
    date_trunc('day', v_now) + INTERVAL '19 hours 5 minutes',
    'Triunfo',
    -25.9490,
    32.6020
  );
  PERFORM public.seed_deligo_demo_order(
    'seed-demo-hour-21',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'delivered',
    6800,
    150,
    date_trunc('day', v_now) + INTERVAL '21 hours 25 minutes',
    'Triunfo',
    -25.9490,
    32.6020
  );

  PERFORM public.seed_deligo_demo_order(
    'seed-demo-day-1',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'delivered',
    12500,
    100,
    date_trunc('day', v_now - INTERVAL '1 day') + INTERVAL '12 hours 10 minutes',
    'Polana',
    -25.9540,
    32.5900
  );
  PERFORM public.seed_deligo_demo_order(
    'seed-demo-day-2',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'delivered',
    15200,
    100,
    date_trunc('day', v_now - INTERVAL '2 days') + INTERVAL '19 hours',
    'Polana',
    -25.9540,
    32.5900
  );
  PERFORM public.seed_deligo_demo_order(
    'seed-demo-day-3',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'delivered',
    13800,
    100,
    date_trunc('day', v_now - INTERVAL '3 days') + INTERVAL '13 hours',
    'Sommerschield',
    -25.9540,
    32.5900
  );
  PERFORM public.seed_deligo_demo_order(
    'seed-demo-day-4',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'delivered',
    17600,
    120,
    date_trunc('day', v_now - INTERVAL '4 days') + INTERVAL '20 hours',
    'Maputo',
    -25.9540,
    32.5900
  );
  PERFORM public.seed_deligo_demo_order(
    'seed-demo-day-5',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'delivered',
    24300,
    150,
    date_trunc('day', v_now - INTERVAL '5 days') + INTERVAL '19 hours 10 minutes',
    'Maputo',
    -25.9540,
    32.5900
  );
  PERFORM public.seed_deligo_demo_order(
    'seed-demo-day-6',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'delivered',
    31900,
    150,
    date_trunc('day', v_now - INTERVAL '6 days') + INTERVAL '20 hours 5 minutes',
    'Maputo',
    -25.9540,
    32.5900
  );

  PERFORM public.seed_deligo_demo_order(
    'seed-demo-late-1',
    v_client_id,
    v_restaurant_id,
    NULL,
    'accepted',
    860,
    100,
    v_now - INTERVAL '2 hours 30 minutes',
    'Maputo',
    -25.9500,
    32.6000
  );
  PERFORM public.seed_deligo_demo_order(
    'seed-demo-late-2',
    v_client_id,
    v_restaurant_id,
    NULL,
    'preparing',
    920,
    120,
    v_now - INTERVAL '2 hours 10 minutes',
    'Maputo',
    -25.9500,
    32.6000
  );
  PERFORM public.seed_deligo_demo_order(
    'seed-demo-late-3',
    v_client_id,
    v_restaurant_id,
    NULL,
    'ready',
    740,
    100,
    v_now - INTERVAL '95 minutes',
    'Maputo',
    -25.9500,
    32.6000
  );
  PERFORM public.seed_deligo_demo_order(
    'seed-demo-cancelled',
    v_client_id,
    v_restaurant_id,
    NULL,
    'cancelled',
    680,
    0,
    v_now - INTERVAL '5 hours',
    'Retirar no restaurante',
    NULL,
    NULL
  );

  PERFORM public.seed_deligo_demo_order(
    'seed-demo-review-good',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'completed',
    1180,
    150,
    v_now - INTERVAL '8 days',
    'Sommerschield',
    -25.9540,
    32.5900
  );

  PERFORM public.seed_deligo_demo_order(
    'seed-demo-review-bad',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'completed',
    910,
    100,
    v_now - INTERVAL '9 days',
    'Polana',
    -25.9540,
    32.5900
  );

  FOR v_item IN
    SELECT p.payment_ref, p.order_id
    FROM public.payments p
    WHERE p.payment_ref IN ('seed-demo-review-good', 'seed-demo-review-bad', 'seed-demo-day-2', 'seed-demo-day-4')
  LOOP
    IF v_item.payment_ref = 'seed-demo-review-good' THEN
      IF NOT EXISTS (SELECT 1 FROM public.reviews WHERE order_id = v_item.order_id) THEN
        IF v_review_user_column IS NULL THEN
          EXECUTE '
            INSERT INTO public.reviews (id, order_id, rating, comment, created_at)
            VALUES (gen_random_uuid(), $1, 5, $2, NOW())'
          USING v_item.order_id, 'Comida excelente, chegou quente e muito bem embalada.';
        ELSE
          EXECUTE format(
            'INSERT INTO public.reviews (id, order_id, %I, rating, comment, created_at)
             VALUES (gen_random_uuid(), $1, $2, 5, $3, NOW())',
            v_review_user_column
          )
          USING v_item.order_id, v_client_id, 'Comida excelente, chegou quente e muito bem embalada.';
        END IF;
      END IF;
    ELSIF v_item.payment_ref = 'seed-demo-review-bad' THEN
      IF NOT EXISTS (SELECT 1 FROM public.reviews WHERE order_id = v_item.order_id) THEN
        IF v_review_user_column IS NULL THEN
          EXECUTE '
            INSERT INTO public.reviews (id, order_id, rating, comment, created_at)
            VALUES (gen_random_uuid(), $1, 2, $2, NOW())'
          USING v_item.order_id, 'Demorou mais do que o esperado e a bebida veio indisponível.';
        ELSE
          EXECUTE format(
            'INSERT INTO public.reviews (id, order_id, %I, rating, comment, created_at)
             VALUES (gen_random_uuid(), $1, $2, 2, $3, NOW())',
            v_review_user_column
          )
          USING v_item.order_id, v_client_id, 'Demorou mais do que o esperado e a bebida veio indisponível.';
        END IF;
      END IF;
    ELSIF v_item.payment_ref = 'seed-demo-day-2' THEN
      IF NOT EXISTS (SELECT 1 FROM public.reviews WHERE order_id = v_item.order_id) THEN
        IF v_review_user_column IS NULL THEN
          EXECUTE '
            INSERT INTO public.reviews (id, order_id, rating, comment, created_at)
            VALUES (gen_random_uuid(), $1, 3, $2, NOW())'
          USING v_item.order_id, 'Bom prato, mas o tempo de preparo pode melhorar.';
        ELSE
          EXECUTE format(
            'INSERT INTO public.reviews (id, order_id, %I, rating, comment, created_at)
             VALUES (gen_random_uuid(), $1, $2, 3, $3, NOW())',
            v_review_user_column
          )
          USING v_item.order_id, v_client_id, 'Bom prato, mas o tempo de preparo pode melhorar.';
        END IF;
      END IF;
    ELSE
      IF NOT EXISTS (SELECT 1 FROM public.reviews WHERE order_id = v_item.order_id) THEN
        IF v_review_user_column IS NULL THEN
          EXECUTE '
            INSERT INTO public.reviews (id, order_id, rating, comment, created_at)
            VALUES (gen_random_uuid(), $1, 5, $2, NOW())'
          USING v_item.order_id, 'Atendimento muito bom e entrega rápida.';
        ELSE
          EXECUTE format(
            'INSERT INTO public.reviews (id, order_id, %I, rating, comment, created_at)
             VALUES (gen_random_uuid(), $1, $2, 5, $3, NOW())',
            v_review_user_column
          )
          USING v_item.order_id, v_client_id, 'Atendimento muito bom e entrega rápida.';
        END IF;
      END IF;
    END IF;
  END LOOP;

  INSERT INTO public.push_notifications (id, user_id, title, body, data, created_at)
  SELECT gen_random_uuid(), v_courier_id, 'Novo pedido disponível', 'Deligo Restaurante tem um pedido perto de você.', jsonb_build_object('restaurant_id', v_restaurant_id), NOW()
  WHERE NOT EXISTS (
    SELECT 1 FROM public.push_notifications
    WHERE user_id = v_courier_id
      AND title = 'Novo pedido disponível'
  );

  INSERT INTO public.push_notifications (id, user_id, title, body, data, created_at)
  SELECT gen_random_uuid(), v_client_id, 'Pedido a caminho', 'Deligo Biker já está com o seu pedido.', jsonb_build_object('restaurant_id', v_restaurant_id), NOW()
  WHERE NOT EXISTS (
    SELECT 1 FROM public.push_notifications
    WHERE user_id = v_client_id
      AND title = 'Pedido a caminho'
  );
END $$;
DROP FUNCTION IF EXISTS public.seed_deligo_demo_order(TEXT, UUID, UUID, UUID, TEXT, NUMERIC, NUMERIC, TIMESTAMPTZ, TEXT, NUMERIC, NUMERIC);
COMMIT;
