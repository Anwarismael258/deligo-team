-- Registration/profile hardening + Deligo Restaurante seed data

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS neighborhood TEXT,
  ADD COLUMN IF NOT EXISTS city TEXT,
  ADD COLUMN IF NOT EXISTS mobile_operator TEXT,
  ADD COLUMN IF NOT EXISTS preferred_payment_method TEXT,
  ADD COLUMN IF NOT EXISTS payment_contact TEXT;
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS rating NUMERIC,
  ADD COLUMN IF NOT EXISTS is_open BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS opening_time TEXT,
  ADD COLUMN IF NOT EXISTS closing_time TEXT,
  ADD COLUMN IF NOT EXISTS estimated_delivery_time INTEGER;
ALTER TABLE public.menu_items
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE public.menu_items
  ADD COLUMN IF NOT EXISTS category TEXT,
  ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT TRUE;
DO $$
DECLARE
  v_restaurant_owner_id UUID;
  v_restaurant_id UUID;
  v_client_id UUID;
  v_courier_id UUID;
BEGIN
  SELECT id INTO v_restaurant_owner_id
  FROM auth.users
  WHERE email = 'anis.justwork@gmail.com'
  LIMIT 1;

  SELECT id INTO v_client_id
  FROM auth.users
  WHERE email = 'anwarismael258@gmail.com'
  LIMIT 1;

  SELECT id INTO v_courier_id
  FROM auth.users
  WHERE email = 'youngmonster199@gmail.com'
  LIMIT 1;

  IF v_client_id IS NOT NULL THEN
    UPDATE public.profiles
    SET
      full_name = COALESCE(NULLIF(full_name, ''), 'Anwar Ismael'),
      phone = COALESCE(NULLIF(phone, ''), '+258877688695'),
      role = COALESCE(NULLIF(role, ''), 'client'),
      preferred_payment_method = COALESCE(NULLIF(preferred_payment_method, ''), 'emola'),
      payment_contact = COALESCE(NULLIF(payment_contact, ''), '877688695'),
      mobile_operator = COALESCE(NULLIF(mobile_operator, ''), 'movitel'),
      updated_at = NOW()
    WHERE id = v_client_id OR user_id = v_client_id;
  END IF;

  IF v_courier_id IS NOT NULL THEN
    UPDATE public.profiles
    SET
      full_name = COALESCE(NULLIF(full_name, ''), 'Deligo Biker'),
      phone = COALESCE(NULLIF(phone, ''), '+258841130015'),
      role = COALESCE(NULLIF(role, ''), 'courier'),
      kyc_status = 'approved',
      preferred_payment_method = COALESCE(NULLIF(preferred_payment_method, ''), 'm-pesa'),
      payment_contact = COALESCE(NULLIF(payment_contact, ''), '841130015'),
      mobile_operator = COALESCE(NULLIF(mobile_operator, ''), 'vodacom'),
      updated_at = NOW()
    WHERE id = v_courier_id OR user_id = v_courier_id;
  END IF;

  IF v_restaurant_owner_id IS NOT NULL THEN
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

    SELECT id INTO v_restaurant_id
    FROM public.restaurants
    WHERE owner_id = v_restaurant_owner_id
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
        image_url
      )
      VALUES (
        v_restaurant_owner_id,
        'Deligo Restaurante',
        'Cozinha urbana com pizzas, burgers, frango crocante e combos rápidos para a cidade.',
        '+258851709807',
        'Av. Julius Nyerere, Maputo',
        'Polana',
        'Maputo',
        TRUE,
        'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80'
      )
      RETURNING id INTO v_restaurant_id;
    ELSE
      UPDATE public.restaurants
      SET
        name = 'Deligo Restaurante',
        description = 'Cozinha urbana com pizzas, burgers, frango crocante e combos rápidos para a cidade.',
        phone = '+258851709807',
        address = 'Av. Julius Nyerere, Maputo',
        neighborhood = COALESCE(NULLIF(neighborhood, ''), 'Polana'),
        city = COALESCE(NULLIF(city, ''), 'Maputo'),
        is_open = TRUE,
        image_url = COALESCE(
          NULLIF(image_url, ''),
          'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80'
        )
      WHERE id = v_restaurant_id;
    END IF;

    IF v_restaurant_id IS NOT NULL THEN
      INSERT INTO public.menu_items (
        restaurant_id,
        name,
        description,
        price,
        image_url,
        category,
        is_available
      )
      SELECT
        v_restaurant_id,
        seeded.name,
        seeded.description,
        seeded.price,
        seeded.image_url,
        seeded.category,
        TRUE
      FROM (
        VALUES
          (
            'Burger Deligo',
            'Burger artesanal com queijo, bacon crocante e molho especial da casa.',
            480,
            'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=1200&q=80',
            'Burgers'
          ),
          (
            'Pizza Mozzarella Suprema',
            'Pizza média com molho de tomate fresco, mozzarella e manjericão.',
            690,
            'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=1200&q=80',
            'Pizzas'
          ),
          (
            'Frango Crocante Deluxe',
            'Frango empanado com batatas rústicas e molho picante suave.',
            520,
            'https://images.unsplash.com/photo-1562967914-608f82629710?auto=format&fit=crop&w=1200&q=80',
            'Combos'
          ),
          (
            'Wrap de Frango Grelhado',
            'Wrap leve com frango grelhado, legumes frescos e molho de iogurte.',
            390,
            'https://images.unsplash.com/photo-1608039755401-742074f0548d?auto=format&fit=crop&w=1200&q=80',
            'Wraps'
          ),
          (
            'Cheesecake de Morango',
            'Sobremesa cremosa com cobertura de morango e base crocante.',
            260,
            'https://images.unsplash.com/photo-1533134242443-d4fd215305ad?auto=format&fit=crop&w=1200&q=80',
            'Sobremesas'
          )
      ) AS seeded(name, description, price, image_url, category)
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.menu_items mi
        WHERE mi.restaurant_id = v_restaurant_id
          AND mi.name = seeded.name
      );

      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'restaurants'
          AND column_name = 'rating'
      ) THEN
        UPDATE public.restaurants
        SET rating = 4.8
        WHERE id = v_restaurant_id;
      END IF;
    END IF;
  END IF;
END $$;
