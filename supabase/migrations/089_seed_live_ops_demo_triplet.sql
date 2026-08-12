DO $$
DECLARE
  v_client_id uuid := '680a7827-68fe-49fa-b005-62e148a6e2b4';
  v_restaurant_owner_id uuid := 'feadf74b-2d43-4e65-ab13-afc02e5837a4';
  v_courier_id uuid := '8df3245f-39cd-4364-9649-50873599fc2c';
  v_active_order_id uuid := 'f0d3a111-3df2-4c58-9f34-1e9f00000089';
  v_reviewed_order_id uuid := 'f0d3a112-3df2-4c58-9f34-1e9f00000089';
  v_restaurant_id uuid;
  v_menu_item_id uuid;
BEGIN
  SELECT id
  INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_restaurant_owner_id
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1;

  IF v_restaurant_id IS NULL THEN
    RAISE NOTICE 'Live ops seed skipped: restaurante nao encontrado.';
    RETURN;
  END IF;

  SELECT id
  INTO v_menu_item_id
  FROM public.menu_items
  WHERE restaurant_id = v_restaurant_id
    AND COALESCE(is_available, true) = true
    AND COALESCE(stock_quantity, 0) > 0
  ORDER BY created_at ASC NULLS LAST, name ASC
  LIMIT 1;

  IF v_menu_item_id IS NULL THEN
    SELECT id
    INTO v_menu_item_id
    FROM public.menu_items
    WHERE restaurant_id = v_restaurant_id
    ORDER BY created_at ASC NULLS LAST, name ASC
    LIMIT 1;
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
  WHERE order_id IN (v_active_order_id, v_reviewed_order_id);

  DELETE FROM public.courier_reviews
  WHERE order_id = v_reviewed_order_id;

  DELETE FROM public.menu_item_review_likes
  WHERE review_id IN (
    SELECT id FROM public.menu_item_reviews
    WHERE reviewer_id = v_client_id
      AND menu_item_id = v_menu_item_id
      AND comment IN (
        'Hamburguer muito bom. O pao veio macio e a entrega correu super bem.',
        'Gostei muito do sabor e quero repetir este prato em breve.'
      )
  );

  DELETE FROM public.menu_item_reviews
  WHERE reviewer_id = v_client_id
    AND menu_item_id = v_menu_item_id
    AND comment IN (
      'Hamburguer muito bom. O pao veio macio e a entrega correu super bem.',
      'Gostei muito do sabor e quero repetir este prato em breve.'
    );

  DELETE FROM public.deliveries
  WHERE order_id IN (v_active_order_id, v_reviewed_order_id);

  DELETE FROM public.order_items
  WHERE order_id IN (v_active_order_id, v_reviewed_order_id);

  DELETE FROM public.payments
  WHERE order_id IN (v_active_order_id, v_reviewed_order_id);

  DELETE FROM public.reviews
  WHERE order_id IN (v_active_order_id, v_reviewed_order_id);

  DELETE FROM public.orders
  WHERE id IN (v_active_order_id, v_reviewed_order_id);

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
  VALUES
    (
      v_active_order_id,
      v_client_id,
      v_client_id,
      v_restaurant_id,
      v_courier_id,
      'courier_assigned',
      980,
      980,
      'completed',
      120,
      64.8,
      'Bairro Coop, Rua B, Casa do Anwar',
      -25.9592,
      32.6054,
      false,
      now() - interval '22 minutes',
      now() - interval '4 minutes'
    ),
    (
      v_reviewed_order_id,
      v_client_id,
      v_client_id,
      v_restaurant_id,
      v_courier_id,
      'delivered',
      1130,
      1130,
      'completed',
      150,
      74.4,
      'Bairro Coop, Rua B, Casa do Anwar',
      -25.9592,
      32.6054,
      true,
      now() - interval '1 day',
      now() - interval '22 hours'
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
  VALUES
    (gen_random_uuid(), v_active_order_id, v_menu_item_id, 2, 430, 430, 860, now() - interval '22 minutes'),
    (gen_random_uuid(), v_reviewed_order_id, v_menu_item_id, 2, 490, 490, 980, now() - interval '1 day');

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
  VALUES
    (gen_random_uuid(), v_active_order_id, 980, 'internal_wallet', 'LIVE-DEMO-ACTIVE', 'wallet', 'completed', 'LIVE-DEMO-ACTIVE', 0, now() - interval '21 minutes', now() - interval '20 minutes'),
    (gen_random_uuid(), v_reviewed_order_id, 1130, 'internal_wallet', 'LIVE-DEMO-REVIEW', 'wallet', 'completed', 'LIVE-DEMO-REVIEW', 0, now() - interval '1 day', now() - interval '1 day');

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
  VALUES
    (
      gen_random_uuid(),
      v_active_order_id,
      v_courier_id,
      -25.9548,
      32.6021,
      -25.9592,
      32.6054,
      -25.9564,
      32.6038,
      'courier_assigned',
      now() - interval '20 minutes',
      now() - interval '3 minutes'
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
    (gen_random_uuid(), v_active_order_id, v_client_id, 'ANWAR', 'client', 'Boa noite. O meu portao fica ao lado do portao verde do vizinho.', now() - interval '20 minutes'),
    (gen_random_uuid(), v_active_order_id, v_restaurant_owner_id, 'Deligo Restaurante', 'restaurant', 'Recebemos o pedido e ja estamos a fechar a embalagem.', now() - interval '18 minutes'),
    (gen_random_uuid(), v_active_order_id, v_courier_id, 'DELIGO BIKER', 'courier', 'Perfeito. Assim que eu sair do restaurante partilho a minha rota aqui.', now() - interval '16 minutes'),
    (gen_random_uuid(), v_reviewed_order_id, v_client_id, 'ANWAR', 'client', 'Entrega tranquila. Obrigado pela atencao de todos.', now() - interval '23 hours'),
    (gen_random_uuid(), v_reviewed_order_id, v_restaurant_owner_id, 'Deligo Restaurante', 'restaurant', 'Obrigado pelo pedido, Anwar. Vamos manter esse padrao.', now() - interval '22 hours 50 minutes'),
    (gen_random_uuid(), v_reviewed_order_id, v_courier_id, 'DELIGO BIKER', 'courier', 'Fico feliz que tenha corrido bem. Ate ao proximo pedido!', now() - interval '22 hours 45 minutes');

  INSERT INTO public.menu_item_reviews (
    id,
    menu_item_id,
    reviewer_id,
    reviewer_name,
    rating,
    comment,
    created_at
  )
  VALUES (
    gen_random_uuid(),
    v_menu_item_id,
    v_client_id,
    'ANWAR',
    5,
    'Hamburguer muito bom. O pao veio macio e a entrega correu super bem.',
    now() - interval '22 hours 30 minutes'
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
    v_reviewed_order_id,
    v_courier_id,
    v_client_id,
    'ANWAR',
    5,
    'Estafeta simpatico, comunicou bem no chat e chegou com a encomenda em otimo estado.',
    now() - interval '22 hours'
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
    current_latitude = -25.9564,
    current_longitude = 32.6038,
    updated_at = now()
  WHERE id = v_courier_id;
END $$;
