DO $$
DECLARE
  v_client_id uuid;
  v_restaurant_owner_id uuid;
  v_courier_id uuid;
  v_restaurant_id uuid;
  v_menu_item_id uuid;
  v_menu_item_name text;
  v_menu_item_price numeric := 430;
  v_order_id uuid := 'f0d3a120-3df2-4c58-9f34-1e9f00000094';
  v_created_at timestamptz := now() - interval '1 hour 35 minutes';
  v_accepted_at timestamptz := now() - interval '1 hour 26 minutes';
  v_ready_at timestamptz := now() - interval '1 hour 8 minutes';
  v_delivered_at timestamptz := now() - interval '42 minutes';
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
    RAISE NOTICE 'Seed 094 ignorado: utilizadores base nao encontrados.';
    RETURN;
  END IF;

  SELECT id
  INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_restaurant_owner_id
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1;

  IF v_restaurant_id IS NULL THEN
    RAISE NOTICE 'Seed 094 ignorado: restaurante nao encontrado.';
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
    RAISE NOTICE 'Seed 094 ignorado: prato do restaurante nao encontrado.';
    RETURN;
  END IF;

  v_subtotal := v_menu_item_price * 2;
  v_total := v_subtotal + v_delivery_fee;

  UPDATE public.profiles
  SET
    full_name = CASE
      WHEN id = v_client_id THEN 'ANWAR'
      WHEN id = v_restaurant_owner_id THEN 'Deligo Restaurante'
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
    'Sommerschield, próximo ao Polana Shopping - Casa do Anwar',
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
    2,
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
    'LIVE-DEMO-COMPLETE-094',
    'wallet',
    'completed',
    'LIVE-DEMO-COMPLETE-094',
    0,
    v_created_at + interval '3 minutes',
    v_created_at + interval '3 minutes'
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
    'https://picsum.photos/seed/deligo-proof-094/900/600',
    'Entrega concluída com confirmação do cliente. Pedido entregue sem incidentes.',
    v_delivered_at,
    -25.9592,
    32.6054,
    v_created_at + interval '35 minutes',
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
      'Boa noite. O pedido ' || left(v_order_id::text, 8) || ' pode tocar no portão azul. O prato escolhido foi ' || v_menu_item_name || '.',
      v_created_at + interval '4 minutes'
    ),
    (
      gen_random_uuid(),
      v_order_id,
      v_restaurant_owner_id,
      'Deligo Restaurante',
      'restaurant',
      'Pedido confirmado às ' || to_char(v_accepted_at, 'HH24:MI') || '. Já estamos a preparar ' || v_menu_item_name || ' com todo o cuidado.',
      v_accepted_at
    ),
    (
      gen_random_uuid(),
      v_order_id,
      v_courier_id,
      'DELIGO BIKER',
      'courier',
      'Perfeito. Recolhi o pedido e sigo para a entrega. Hora estimada: ' || to_char(v_delivered_at, 'HH24:MI') || '.',
      v_ready_at + interval '8 minutes'
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
        'delivered_at', v_delivered_at
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

  RAISE NOTICE 'Seed 094 concluído. Pedido % com prato % criado para cliente/restaurante/estafeta.', v_order_id, v_menu_item_name;
END $$;
