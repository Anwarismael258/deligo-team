-- Ensure Deligo Restaurante is visible to the client and has available dishes.
DO $$
DECLARE
  v_restaurant_owner_id uuid;
  v_restaurant_id uuid;
BEGIN
  SELECT id INTO v_restaurant_owner_id
  FROM auth.users
  WHERE email = 'anis.justwork@gmail.com'
  LIMIT 1;

  IF v_restaurant_owner_id IS NULL THEN
    RAISE NOTICE 'Skipping Deligo restaurant seed: owner user not found.';
    RETURN;
  END IF;

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
    image_url,
    rating,
    is_open,
    opening_time,
    closing_time,
    estimated_delivery_time,
    created_at,
    updated_at
  )
  VALUES (
    gen_random_uuid(),
    v_restaurant_owner_id,
    'Deligo Restaurante',
    'Restaurante urbano com pratos fortes, combos e entrega rápida em Maputo.',
    '+258851709807',
    'Av. Julius Nyerere, Maputo',
    'Polana',
    'Maputo',
    -25.9645,
    32.5880,
    'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80',
    4.8,
    true,
    '08:00',
    '23:00',
    25,
    now(),
    now()
  )
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_restaurant_owner_id
  ORDER BY created_at ASC
  LIMIT 1;

  UPDATE public.restaurants
  SET
    name = COALESCE(NULLIF(name, ''), 'Deligo Restaurante'),
    description = COALESCE(NULLIF(description, ''), 'Restaurante urbano com pratos fortes, combos e entrega rápida em Maputo.'),
    phone = COALESCE(NULLIF(phone, ''), '+258851709807'),
    address = COALESCE(NULLIF(address, ''), 'Av. Julius Nyerere, Maputo'),
    neighborhood = COALESCE(NULLIF(neighborhood, ''), 'Polana'),
    city = COALESCE(NULLIF(city, ''), 'Maputo'),
    latitude = COALESCE(latitude, -25.9645),
    longitude = COALESCE(longitude, 32.5880),
    image_url = COALESCE(NULLIF(image_url, ''), 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80'),
    rating = COALESCE(rating, 4.8),
    is_open = true,
    estimated_delivery_time = COALESCE(estimated_delivery_time, 25),
    updated_at = now()
  WHERE id = v_restaurant_id;

  IF v_restaurant_id IS NULL THEN
    RAISE NOTICE 'Skipping menu seed: restaurant not found.';
    RETURN;
  END IF;

  INSERT INTO public.menu_items (
    id,
    restaurant_id,
    name,
    description,
    price,
    image_url,
    category,
    is_available,
    stock_quantity,
    item_rating,
    prep_time_minutes,
    created_at,
    updated_at
  )
  SELECT
    gen_random_uuid(),
    v_restaurant_id,
    item_name,
    item_description,
    item_price,
    item_image,
    item_category,
    true,
    item_stock,
    item_rating,
    item_prep,
    now(),
    now()
  FROM (
    VALUES
      ('Combo Executivo', 'Arroz, frango grelhado, salada fresca e bebida.', 850::numeric, 'https://images.unsplash.com/photo-1512058564366-18510be2db19?auto=format&fit=crop&w=1200&q=80', '🔥 Promoções', 12, 4.9::numeric, 20),
      ('Matapa Especial', 'Matapa cremosa com camarão e arroz branco.', 980::numeric, 'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=1200&q=80', '🌍 Especialidades', 9, 4.8::numeric, 28),
      ('Burger Deligo', 'Hambúrguer artesanal com queijo, bacon e molho da casa.', 720::numeric, 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=1200&q=80', '🍔 Fast Food', 14, 4.7::numeric, 18),
      ('Batata Crocante', 'Batatas fritas crocantes com molho especial.', 260::numeric, 'https://images.unsplash.com/photo-1576107232684-1279f390859f?auto=format&fit=crop&w=1200&q=80', '🍟 Acompanhamentos', 20, 4.6::numeric, 12),
      ('Sumo Natural', 'Sumo natural gelado de manga e laranja.', 180::numeric, 'https://images.unsplash.com/photo-1622597467836-f3e6706b7f0f?auto=format&fit=crop&w=1200&q=80', '🥤 Bebidas', 25, 4.5::numeric, 6)
  ) AS seed(item_name, item_description, item_price, item_image, item_category, item_stock, item_rating, item_prep)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.menu_items mi
    WHERE mi.restaurant_id = v_restaurant_id
      AND lower(mi.name) = lower(seed.item_name)
  );

  UPDATE public.menu_items
  SET
    is_available = true,
    stock_quantity = COALESCE(stock_quantity, 10),
    item_rating = COALESCE(item_rating, 4.6),
    prep_time_minutes = COALESCE(prep_time_minutes, 20),
    updated_at = now()
  WHERE restaurant_id = v_restaurant_id;
END $$;
