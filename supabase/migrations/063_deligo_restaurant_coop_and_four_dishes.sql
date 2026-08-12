DO $$
DECLARE
  v_owner_id uuid;
  v_restaurant_id uuid;
BEGIN
  SELECT id INTO v_owner_id
  FROM auth.users
  WHERE email = 'anis.justwork@gmail.com'
  LIMIT 1;

  IF v_owner_id IS NULL THEN
    RAISE NOTICE 'Usuario do restaurante nao encontrado: anis.justwork@gmail.com';
    RETURN;
  END IF;

  SELECT id INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_owner_id
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1;

  IF v_restaurant_id IS NULL THEN
    INSERT INTO public.restaurants (
      owner_id,
      name,
      description,
      phone,
      address,
      neighborhood,
      city,
      is_open,
      opening_time,
      closing_time,
      estimated_delivery_time,
      rating
    ) VALUES (
      v_owner_id,
      'Deligo Restaurante',
      'Sabores urbanos, fast food e pratos principais preparados para entrega rapida.',
      '851709807',
      'Bairro Coop, Maputo',
      'Coop',
      'Maputo',
      true,
      '08:00',
      '22:00',
      35,
      4.7
    )
    RETURNING id INTO v_restaurant_id;
  ELSE
    UPDATE public.restaurants
    SET
      name = 'Deligo Restaurante',
      description = COALESCE(description, 'Sabores urbanos, fast food e pratos principais preparados para entrega rapida.'),
      phone = COALESCE(phone, '851709807'),
      address = 'Bairro Coop, Maputo',
      neighborhood = 'Coop',
      city = COALESCE(city, 'Maputo'),
      is_open = true,
      opening_time = COALESCE(opening_time, '08:00'),
      closing_time = COALESCE(closing_time, '22:00'),
      estimated_delivery_time = COALESCE(estimated_delivery_time, 35),
      rating = COALESCE(rating, 4.7)
    WHERE id = v_restaurant_id;
  END IF;

  INSERT INTO public.menu_items (
    restaurant_id,
    name,
    description,
    category,
    price,
    image_url,
    is_available,
    stock_quantity,
    item_rating,
    prep_time_minutes
  )
  SELECT *
  FROM (
    VALUES
      (
        v_restaurant_id,
        'Burger Deligo Especial',
        'Hamburguer artesanal com queijo, bacon crocante, molho da casa e batata rustica.',
        '🍔 Fast Food',
        450::numeric,
        NULL::text,
        true,
        18,
        4.8::numeric,
        25
      ),
      (
        v_restaurant_id,
        'Frango Grelhado com Arroz',
        'Frango grelhado no ponto, arroz temperado e salada fresca.',
        '🥘 Pratos principais',
        520::numeric,
        NULL::text,
        true,
        14,
        4.7::numeric,
        30
      ),
      (
        v_restaurant_id,
        'Combo Shawarma + Batata + Refri',
        'Combo promocional com shawarma de frango, batata frita e refrigerante.',
        '🔥 Promoções',
        600::numeric,
        NULL::text,
        true,
        10,
        4.6::numeric,
        20
      ),
      (
        v_restaurant_id,
        'Mousse de Chocolate Premium',
        'Sobremesa cremosa de chocolate com finalizacao suave e elegante.',
        '🍰 Sobremesas',
        220::numeric,
        NULL::text,
        true,
        9,
        4.9::numeric,
        8
      )
  ) AS seeded(
    restaurant_id,
    name,
    description,
    category,
    price,
    image_url,
    is_available,
    stock_quantity,
    item_rating,
    prep_time_minutes
  )
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.menu_items mi
    WHERE mi.restaurant_id = v_restaurant_id
      AND mi.name = seeded.name
  );
END $$;
