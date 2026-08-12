DO $$
DECLARE
  v_client_id uuid;
  v_restaurant_owner_id uuid;
  v_courier_id uuid;
  v_order_id uuid := 'f0d3a120-3df2-4c58-9f34-1e9f00000090';
  v_restaurant_id uuid;
  v_menu_item_id uuid;
  v_review_image_url text := 'https://picsum.photos/seed/deligo-review-prato/900/600';
BEGIN
  SELECT id
  INTO v_client_id
  FROM auth.users
  WHERE email = 'anwarismael258@gmail.com'
  LIMIT 1;

  IF v_client_id IS NULL THEN
    v_client_id := '680a7827-68fe-49fa-b005-62e148a6e2b4';
  END IF;

  SELECT id
  INTO v_restaurant_owner_id
  FROM auth.users
  WHERE email = 'anis.justwork@gmail.com'
  LIMIT 1;

  IF v_restaurant_owner_id IS NULL THEN
    v_restaurant_owner_id := 'feadf74b-2d43-4e65-ab13-afc02e5837a4';
  END IF;

  SELECT id
  INTO v_courier_id
  FROM auth.users
  WHERE email = 'youngmonster199@gmail.com'
  LIMIT 1;

  IF v_courier_id IS NULL THEN
    v_courier_id := '8df3245f-39cd-4364-9649-50873599fc2c';
  END IF;

  SELECT id
  INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_restaurant_owner_id
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1;

  IF v_restaurant_id IS NULL THEN
    RAISE NOTICE 'Seed 090 ignorado: restaurante nao encontrado.';
    RETURN;
  END IF;

  SELECT id
  INTO v_menu_item_id
  FROM public.menu_items
  WHERE restaurant_id = v_restaurant_id
  ORDER BY COALESCE(is_available, true) DESC, COALESCE(stock_quantity, 0) DESC, created_at ASC NULLS LAST
  LIMIT 1;

  IF v_menu_item_id IS NULL THEN
    RAISE NOTICE 'Seed 090 ignorado: menu item nao encontrado.';
    RETURN;
  END IF;

  UPDATE public.profiles
  SET
    full_name = CASE
      WHEN id = v_client_id THEN 'ANWAR'
      WHEN id = v_restaurant_owner_id THEN 'Deligo restaurante'
      WHEN id = v_courier_id THEN 'DELIGO BIKER'
      ELSE full_name
    END,
    avatar_url = CASE
      WHEN id = v_client_id THEN 'https://i.pravatar.cc/160?img=12'
      WHEN id = v_restaurant_owner_id THEN 'https://i.pravatar.cc/160?img=15'
      WHEN id = v_courier_id THEN 'https://i.pravatar.cc/160?img=18'
      ELSE avatar_url
    END,
    updated_at = now()
  WHERE id IN (v_client_id, v_restaurant_owner_id, v_courier_id);

  DELETE FROM public.messages
  WHERE order_id = v_order_id;

  DELETE FROM public.courier_reviews
  WHERE order_id = v_order_id;

  DELETE FROM public.menu_item_review_likes
  WHERE review_id IN (
    SELECT id
    FROM public.menu_item_reviews
    WHERE menu_item_id = v_menu_item_id
      AND reviewer_id = v_client_id
      AND comment = 'Pedido concluido muito bem. O prato chegou bonito, quente e com sabor forte.'
  );

  DELETE FROM public.menu_item_reviews
  WHERE menu_item_id = v_menu_item_id
    AND reviewer_id = v_client_id
    AND comment = 'Pedido concluido muito bem. O prato chegou bonito, quente e com sabor forte.';

  DELETE FROM public.deliveries
  WHERE order_id = v_order_id;

  DELETE FROM public.order_items
  WHERE order_id = v_order_id;

  DELETE FROM public.payments
  WHERE order_id = v_order_id;

  DELETE FROM public.reviews
  WHERE order_id = v_order_id;

  DELETE FROM public.orders
  WHERE id = v_order_id;

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
    v_courier_id,
    'completed',
    980,
    980,
    'completed',
    120,
    58.8,
    'Bairro Coop, Rua B, Casa do Anwar',
    -25.9592,
    32.6054,
    true,
    now() - interval '3 hours',
    now() - interval '2 hours 10 minutes'
  );

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
    430,
    430,
    860,
    now() - interval '3 hours'
  );

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
    980,
    'internal_wallet',
    'LIVE-DEMO-COMPLETE-090',
    'wallet',
    'completed',
    'LIVE-DEMO-COMPLETE-090',
    0,
    now() - interval '2 hours 58 minutes',
    now() - interval '2 hours 58 minutes'
  );

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
    proof_photo_url,
    proof_notes,
    proof_taken_at,
    proof_latitude,
    proof_longitude,
    created_at,
    updated_at
  )
  VALUES (
    gen_random_uuid(),
    v_order_id,
    v_courier_id,
    -25.9548,
    32.6021,
    -25.9592,
    32.6054,
    -25.9592,
    32.6054,
    'delivered',
    'https://picsum.photos/seed/deligo-proof-090/900/600',
    'Entrega concluida na morada do cliente, sem incidentes.',
    now() - interval '2 hours 12 minutes',
    -25.9592,
    32.6054,
    now() - interval '2 hours 55 minutes',
    now() - interval '2 hours 12 minutes'
  )
  ON CONFLICT DO NOTHING;

  INSERT INTO public.messages (
    id,
    order_id,
    sender_id,
    sender_name,
    sender_role,
    text,
    created_at
  )
  VALUES
    (
      gen_random_uuid(),
      v_order_id,
      v_client_id,
      'ANWAR',
      'client',
      'Boa noite. Podem tocar no portao azul quando chegarem.',
      now() - interval '2 hours 50 minutes'
    ),
    (
      gen_random_uuid(),
      v_order_id,
      v_restaurant_owner_id,
      'Deligo Restaurante',
      'restaurant',
      'Pedido confirmado. Estamos a preparar o prato agora.',
      now() - interval '2 hours 46 minutes'
    ),
    (
      gen_random_uuid(),
      v_order_id,
      v_courier_id,
      'DELIGO BIKER',
      'courier',
      'Perfeito. Assim que sair do restaurante vou atualizar a rota.',
      now() - interval '2 hours 36 minutes'
    );

  INSERT INTO public.menu_item_reviews (
    id,
    menu_item_id,
    reviewer_id,
    reviewer_name,
    rating,
    comment,
    image_url,
    created_at
  )
  VALUES (
    gen_random_uuid(),
    v_menu_item_id,
    v_client_id,
    'ANWAR',
    5,
    'Pedido concluido muito bem. O prato chegou bonito, quente e com sabor forte.',
    v_review_image_url,
    now() - interval '2 hours'
  );

  INSERT INTO public.courier_reviews (
    id,
    order_id,
    courier_id,
    reviewer_id,
    reviewer_name,
    rating,
    comment,
    created_at
  )
  VALUES (
    gen_random_uuid(),
    v_order_id,
    v_courier_id,
    v_client_id,
    'ANWAR',
    5,
    'Entrega pontual, boa comunicacao no chat e muito cuidado com a encomenda.',
    now() - interval '1 hour 58 minutes'
  )
  ON CONFLICT (order_id, reviewer_id) DO UPDATE
  SET
    rating = EXCLUDED.rating,
    comment = EXCLUDED.comment,
    reviewer_name = EXCLUDED.reviewer_name,
    created_at = EXCLUDED.created_at;

  UPDATE public.couriers
  SET
    is_online = true,
    current_latitude = -25.9592,
    current_longitude = 32.6054,
    updated_at = now()
  WHERE id = v_courier_id;
END $$;
