DO $$
DECLARE
  v_client_id uuid;
  v_restaurant_owner_id uuid;
  v_courier_id uuid;
  v_restaurant_id uuid;
  v_menu_item_id uuid;
  v_menu_item_name text;
  v_menu_item_price numeric := 430;
  v_order_id uuid := '2f61d41d-9e7c-4d82-94c8-74f9a1b20099';
  v_created_at timestamptz := now() - interval '2 hours 12 minutes';
  v_paid_at timestamptz := now() - interval '2 hours 7 minutes';
  v_accepted_at timestamptz := now() - interval '1 hour 59 minutes';
  v_ready_at timestamptz := now() - interval '1 hour 24 minutes';
  v_delivered_at timestamptz := now() - interval '48 minutes';
  v_delivery_fee numeric := 120;
  v_subtotal numeric;
  v_total numeric;
BEGIN
  SELECT id
  INTO v_client_id
  FROM auth.users
  WHERE email = 'anwarismael258@gmail.com'
  LIMIT 1;

  SELECT id
  INTO v_restaurant_owner_id
  FROM auth.users
  WHERE email = 'anis.justwork@gmail.com'
  LIMIT 1;

  SELECT id
  INTO v_courier_id
  FROM auth.users
  WHERE email = 'youngmonster199@gmail.com'
  LIMIT 1;

  IF v_client_id IS NULL OR v_restaurant_owner_id IS NULL OR v_courier_id IS NULL THEN
    RAISE NOTICE 'Seed 099 ignorado: utilizadores base nao encontrados.';
    RETURN;
  END IF;

  SELECT id
  INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_restaurant_owner_id
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1;

  IF v_restaurant_id IS NULL THEN
    RAISE NOTICE 'Seed 099 ignorado: restaurante nao encontrado.';
    RETURN;
  END IF;

  SELECT
    id,
    COALESCE(NULLIF(name, ''), 'Prato especial Deligo'),
    COALESCE(price, 430)
  INTO v_menu_item_id, v_menu_item_name, v_menu_item_price
  FROM public.menu_items
  WHERE restaurant_id = v_restaurant_id
  ORDER BY COALESCE(is_available, true) DESC,
           COALESCE(stock_quantity, 0) DESC,
           created_at ASC NULLS LAST
  LIMIT 1;

  IF v_menu_item_id IS NULL THEN
    RAISE NOTICE 'Seed 099 ignorado: prato do restaurante nao encontrado.';
    RETURN;
  END IF;

  v_subtotal := v_menu_item_price;
  v_total := v_subtotal + v_delivery_fee;

  DELETE FROM public.messages
  WHERE order_id = v_order_id;

  DELETE FROM public.courier_reviews
  WHERE order_id = v_order_id;

  DELETE FROM public.deliveries
  WHERE order_id = v_order_id;

  DELETE FROM public.order_items
  WHERE order_id = v_order_id;

  DELETE FROM public.payments
  WHERE order_id = v_order_id;

  DELETE FROM public.reviews
  WHERE order_id = v_order_id;

  DELETE FROM public.payment_splits
  WHERE order_id = v_order_id;

  DELETE FROM public.order_disputes
  WHERE order_id = v_order_id;

  DELETE FROM public.order_events
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
    v_total,
    v_total,
    'completed',
    v_delivery_fee,
    ROUND(v_subtotal * 0.06, 2),
    'Sommerschield, próximo ao Polana Shopping - Casa 17 do Anwar',
    -25.9592,
    32.6054,
    true,
    v_created_at,
    v_delivered_at
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
    1,
    v_menu_item_price,
    v_menu_item_price,
    v_subtotal,
    v_created_at
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
    v_total,
    'internal_wallet',
    'LIVE-REAL-COMPLETE-099',
    'wallet',
    'completed',
    'LIVE-REAL-COMPLETE-099',
    0,
    v_paid_at,
    v_paid_at
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
    'https://picsum.photos/seed/deligo-proof-099/900/600',
    'Entrega concluída com prova e confirmação visual no local.',
    v_delivered_at,
    -25.9592,
    32.6054,
    v_ready_at + interval '10 minutes',
    v_delivered_at
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
      'Boa noite. Pedido #' || left(v_order_id::text, 8) || '. Estou na Casa 17 do Anwar, perto do Polana Shopping. O prato escolhido foi ' || v_menu_item_name || '.',
      v_created_at + interval '6 minutes'
    ),
    (
      gen_random_uuid(),
      v_order_id,
      v_restaurant_owner_id,
      'Deligo Restaurante',
      'restaurant',
      'Pedido pago e confirmado às ' || to_char(v_accepted_at, 'HH24:MI') || '. Estamos a preparar ' || v_menu_item_name || ' agora mesmo.',
      v_accepted_at
    ),
    (
      gen_random_uuid(),
      v_order_id,
      v_courier_id,
      'DELIGO BIKER',
      'courier',
      'Pedido recolhido. Vou entregar na Casa 17 do Anwar em cerca de 10 minutos. Número do pedido: ' || left(v_order_id::text, 8) || '.',
      v_ready_at + interval '8 minutes'
    ),
    (
      gen_random_uuid(),
      v_order_id,
      v_client_id,
      'ANWAR',
      'client',
      'Perfeito, fico no portão azul. Obrigado.',
      v_ready_at + interval '12 minutes'
    ),
    (
      gen_random_uuid(),
      v_order_id,
      v_restaurant_owner_id,
      'Deligo Restaurante',
      'restaurant',
      'Obrigado pelo pedido. Qualquer ajuste estamos aqui no chat.',
      v_ready_at + interval '14 minutes'
    );

  INSERT INTO public.order_events (
    id,
    order_id,
    event_type,
    actor_id,
    actor_role,
    new_status,
    metadata,
    created_at
  )
  VALUES
    (
      gen_random_uuid(),
      v_order_id,
      'order_created',
      v_client_id,
      'client',
      'pending',
      jsonb_build_object(
        'message', 'Pedido criado pelo cliente',
        'order_id', v_order_id,
        'menu_item_name', v_menu_item_name
      ),
      v_created_at
    ),
    (
      gen_random_uuid(),
      v_order_id,
      'payment_confirmed',
      v_client_id,
      'client',
      'paid',
      jsonb_build_object(
        'message', 'Pagamento interno confirmado',
        'paid_at', v_paid_at
      ),
      v_paid_at
    ),
    (
      gen_random_uuid(),
      v_order_id,
      'restaurant_confirmed',
      v_restaurant_owner_id,
      'restaurant',
      'accepted',
      jsonb_build_object(
        'message', 'Pedido confirmado pelo restaurante',
        'accepted_at', v_accepted_at
      ),
      v_accepted_at
    ),
    (
      gen_random_uuid(),
      v_order_id,
      'order_ready',
      v_restaurant_owner_id,
      'restaurant',
      'ready',
      jsonb_build_object(
        'message', 'Pedido pronto para recolha',
        'ready_at', v_ready_at
      ),
      v_ready_at
    ),
    (
      gen_random_uuid(),
      v_order_id,
      'courier_assigned',
      v_courier_id,
      'courier',
      'courier_assigned',
      jsonb_build_object(
        'message', 'Estafeta atribuído e a caminho',
        'courier_name', 'DELIGO BIKER'
      ),
      v_ready_at + interval '5 minutes'
    ),
    (
      gen_random_uuid(),
      v_order_id,
      'delivery_completed',
      v_courier_id,
      'courier',
      'completed',
      jsonb_build_object(
        'message', 'Entrega concluída',
        'delivered_at', v_delivered_at,
        'proof_photo_url', 'https://picsum.photos/seed/deligo-proof-099/900/600'
      ),
      v_delivered_at
    );

  UPDATE public.couriers
  SET
    is_online = true,
    current_latitude = -25.9592,
    current_longitude = 32.6054,
    updated_at = now()
  WHERE id = v_courier_id;

  RAISE NOTICE 'Seed 099 concluído. Pedido real % com prato % criado para cliente/restaurante/estafeta.', v_order_id, v_menu_item_name;
END $$;
