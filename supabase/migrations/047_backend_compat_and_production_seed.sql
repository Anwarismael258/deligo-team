BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- Generic updated_at trigger
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- Replace compatibility view with writable table if needed
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_views
    WHERE schemaname = 'public' AND viewname = 'couriers'
  ) THEN
    EXECUTE 'DROP VIEW public.couriers';
  END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.couriers (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  phone TEXT,
  current_latitude NUMERIC(10,8),
  current_longitude NUMERIC(11,8),
  is_online BOOLEAN DEFAULT FALSE,
  vehicle_type TEXT DEFAULT 'motorbike',
  rating NUMERIC DEFAULT 4.8,
  total_deliveries INTEGER DEFAULT 0,
  earnings_today NUMERIC DEFAULT 0,
  acceptance_rate NUMERIC DEFAULT 92,
  cancellation_rate NUMERIC DEFAULT 3,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE IF EXISTS public.couriers
  ADD COLUMN IF NOT EXISTS full_name TEXT,
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS current_latitude NUMERIC(10,8),
  ADD COLUMN IF NOT EXISTS current_longitude NUMERIC(11,8),
  ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS vehicle_type TEXT DEFAULT 'motorbike',
  ADD COLUMN IF NOT EXISTS rating NUMERIC DEFAULT 4.8,
  ADD COLUMN IF NOT EXISTS total_deliveries INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS earnings_today NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS acceptance_rate NUMERIC DEFAULT 92,
  ADD COLUMN IF NOT EXISTS cancellation_rate NUMERIC DEFAULT 3,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE IF EXISTS public.restaurants
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS image_url TEXT,
  ADD COLUMN IF NOT EXISTS neighborhood TEXT,
  ADD COLUMN IF NOT EXISTS city TEXT,
  ADD COLUMN IF NOT EXISTS latitude NUMERIC(10,8),
  ADD COLUMN IF NOT EXISTS longitude NUMERIC(11,8),
  ADD COLUMN IF NOT EXISTS rating NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_open BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS opening_time TEXT,
  ADD COLUMN IF NOT EXISTS closing_time TEXT,
  ADD COLUMN IF NOT EXISTS estimated_delivery_time INTEGER DEFAULT 30,
  ADD COLUMN IF NOT EXISTS wallet_balance NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE IF EXISTS public.menu_items
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS image_url TEXT,
  ADD COLUMN IF NOT EXISTS category TEXT,
  ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE IF EXISTS public.orders
  ADD COLUMN IF NOT EXISTS client_id UUID,
  ADD COLUMN IF NOT EXISTS total_amount NUMERIC,
  ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS delivery_fee NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS admin_commission NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS delivery_address TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS scheduled_for TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS group_code TEXT,
  ADD COLUMN IF NOT EXISTS group_owner_id UUID,
  ADD COLUMN IF NOT EXISTS delivery_latitude NUMERIC(10,8),
  ADD COLUMN IF NOT EXISTS delivery_longitude NUMERIC(11,8),
  ADD COLUMN IF NOT EXISTS confirmed_by_customer BOOLEAN DEFAULT FALSE;
ALTER TABLE IF EXISTS public.order_items
  ADD COLUMN IF NOT EXISTS price NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS unit_price NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS subtotal NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE IF EXISTS public.payments
  ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'wallet',
  ADD COLUMN IF NOT EXISTS transaction_id TEXT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE IF EXISTS public.messages
  ADD COLUMN IF NOT EXISTS sender_name TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS sender_role TEXT DEFAULT 'client';
ALTER TABLE IF EXISTS public.deliveries
  ADD COLUMN IF NOT EXISTS pickup_latitude NUMERIC(10,8),
  ADD COLUMN IF NOT EXISTS pickup_longitude NUMERIC(11,8),
  ADD COLUMN IF NOT EXISTS delivery_latitude NUMERIC(10,8),
  ADD COLUMN IF NOT EXISTS delivery_longitude NUMERIC(11,8),
  ADD COLUMN IF NOT EXISTS current_latitude NUMERIC(10,8),
  ADD COLUMN IF NOT EXISTS current_longitude NUMERIC(11,8),
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE IF EXISTS public.wallets
  ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'MZN',
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
-- Keep old/new column pairs in sync on orders
CREATE OR REPLACE FUNCTION public.sync_order_compat_fields()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.client_id IS NULL AND NEW.customer_id IS NOT NULL THEN
    NEW.client_id = NEW.customer_id;
  END IF;
  IF NEW.customer_id IS NULL AND NEW.client_id IS NOT NULL THEN
    NEW.customer_id = NEW.client_id;
  END IF;

  IF NEW.total_amount IS NULL AND NEW.total IS NOT NULL THEN
    NEW.total_amount = NEW.total;
  END IF;
  IF NEW.total IS NULL AND NEW.total_amount IS NOT NULL THEN
    NEW.total = NEW.total_amount;
  END IF;

  IF NEW.total_amount IS NULL THEN NEW.total_amount = 0; END IF;
  IF NEW.total IS NULL THEN NEW.total = NEW.total_amount; END IF;
  IF NEW.payment_status IS NULL OR NEW.payment_status = '' THEN
    NEW.payment_status = CASE
      WHEN NEW.status IN ('paid', 'accepted', 'preparing', 'ready', 'picked_up', 'delivering', 'in_transit', 'arrived', 'delivered', 'completed')
        THEN 'completed'
      WHEN NEW.status = 'cancelled'
        THEN 'failed'
      ELSE 'pending'
    END;
  END IF;
  IF NEW.delivery_fee IS NULL THEN NEW.delivery_fee = 0; END IF;
  IF NEW.admin_commission IS NULL THEN
    NEW.admin_commission = ROUND((COALESCE(NEW.total_amount, 0) * 0.15)::numeric, 2);
  END IF;
  IF NEW.updated_at IS NULL THEN NEW.updated_at = NOW(); END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_sync_order_compat_fields ON public.orders;
CREATE TRIGGER trg_sync_order_compat_fields
BEFORE INSERT OR UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.sync_order_compat_fields();
UPDATE public.orders
SET
  client_id = COALESCE(client_id, customer_id),
  customer_id = COALESCE(customer_id, client_id),
  total_amount = COALESCE(total_amount, total, 0),
  total = COALESCE(total, total_amount, 0),
  payment_status = COALESCE(NULLIF(payment_status, ''), CASE
    WHEN status IN ('paid', 'accepted', 'preparing', 'ready', 'picked_up', 'delivering', 'in_transit', 'arrived', 'delivered', 'completed') THEN 'completed'
    WHEN status = 'cancelled' THEN 'failed'
    ELSE 'pending'
  END),
  delivery_fee = COALESCE(delivery_fee, 0),
  admin_commission = COALESCE(admin_commission, ROUND((COALESCE(total_amount, total, 0) * 0.15)::numeric, 2)),
  updated_at = COALESCE(updated_at, created_at, NOW())
WHERE TRUE;
UPDATE public.order_items
SET
  price = CASE
    WHEN COALESCE(price, 0) > 0 THEN price
    WHEN COALESCE(unit_price, 0) > 0 THEN unit_price
    WHEN quantity IS NOT NULL AND quantity > 0 AND COALESCE(subtotal, 0) > 0 THEN ROUND((subtotal / quantity)::numeric, 2)
    ELSE COALESCE(price, 0)
  END,
  unit_price = CASE
    WHEN COALESCE(unit_price, 0) > 0 THEN unit_price
    WHEN COALESCE(price, 0) > 0 THEN price
    WHEN quantity IS NOT NULL AND quantity > 0 AND COALESCE(subtotal, 0) > 0 THEN ROUND((subtotal / quantity)::numeric, 2)
    ELSE COALESCE(unit_price, 0)
  END,
  subtotal = CASE
    WHEN COALESCE(subtotal, 0) > 0 THEN subtotal
    ELSE ROUND((COALESCE(unit_price, price, 0) * COALESCE(quantity, 0))::numeric, 2)
  END,
  created_at = COALESCE(created_at, NOW())
WHERE TRUE;
UPDATE public.payments
SET
  payment_method = COALESCE(NULLIF(payment_method, ''), 'wallet'),
  updated_at = COALESCE(updated_at, created_at, NOW())
WHERE TRUE;
UPDATE public.messages
SET
  sender_name = COALESCE(NULLIF(sender_name, ''), 'DeliGo MZ'),
  sender_role = COALESCE(NULLIF(sender_role, ''), 'client')
WHERE TRUE;
UPDATE public.deliveries
SET
  updated_at = COALESCE(updated_at, created_at, NOW()),
  status = COALESCE(NULLIF(status, ''), 'pending')
WHERE TRUE;
UPDATE public.restaurants
SET updated_at = COALESCE(updated_at, created_at, NOW())
WHERE TRUE;
UPDATE public.menu_items
SET
  is_available = COALESCE(is_available, TRUE),
  created_at = COALESCE(created_at, NOW()),
  updated_at = COALESCE(updated_at, created_at, NOW())
WHERE TRUE;
UPDATE public.wallets
SET
  currency = COALESCE(NULLIF(currency, ''), 'MZN'),
  is_active = COALESCE(is_active, TRUE),
  created_at = COALESCE(created_at, NOW()),
  updated_at = COALESCE(updated_at, created_at, NOW())
WHERE TRUE;
-- Robust transactional order creation for current app payload
CREATE OR REPLACE FUNCTION public.create_order_transactional(
  p_restaurant_id UUID,
  p_delivery_address TEXT,
  p_total_amount NUMERIC,
  p_delivery_fee NUMERIC,
  p_payment_method TEXT,
  p_items JSONB,
  p_scheduled_for TIMESTAMPTZ DEFAULT NULL,
  p_group_code TEXT DEFAULT NULL,
  p_delivery_latitude NUMERIC DEFAULT NULL,
  p_delivery_longitude NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_order_id UUID;
  v_item JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  IF p_restaurant_id IS NULL THEN
    RAISE EXCEPTION 'restaurant_id_required';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'items_required';
  END IF;

  INSERT INTO public.orders (
    id,
    client_id,
    customer_id,
    restaurant_id,
    status,
    total_amount,
    total,
    payment_status,
    delivery_fee,
    delivery_address,
    scheduled_for,
    group_code,
    group_owner_id,
    delivery_latitude,
    delivery_longitude,
    created_at,
    updated_at,
    confirmed_by_customer
  ) VALUES (
    gen_random_uuid(),
    v_user_id,
    v_user_id,
    p_restaurant_id,
    'pending',
    p_total_amount,
    p_total_amount,
    'pending',
    COALESCE(p_delivery_fee, 0),
    COALESCE(p_delivery_address, ''),
    p_scheduled_for,
    p_group_code,
    CASE WHEN p_group_code IS NOT NULL THEN v_user_id ELSE NULL END,
    p_delivery_latitude,
    p_delivery_longitude,
    NOW(),
    NOW(),
    FALSE
  ) RETURNING id INTO v_order_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
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
      (v_item->>'menu_item_id')::uuid,
      COALESCE((v_item->>'quantity')::int, 1),
      COALESCE((v_item->>'unit_price')::numeric, 0),
      COALESCE((v_item->>'unit_price')::numeric, 0),
      COALESCE((v_item->>'subtotal')::numeric, 0),
      NOW()
    );
  END LOOP;

  INSERT INTO public.payments (
    id,
    order_id,
    amount,
    payment_method,
    status,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_order_id,
    p_total_amount,
    COALESCE(NULLIF(p_payment_method, ''), 'wallet'),
    'pending',
    NOW(),
    NOW()
  );

  RETURN (
    SELECT jsonb_build_object(
      'id', o.id,
      'client_id', o.client_id,
      'restaurant_id', o.restaurant_id,
      'courier_id', o.courier_id,
      'status', o.status,
      'payment_status', o.payment_status,
      'total_amount', o.total_amount,
      'delivery_fee', o.delivery_fee,
      'delivery_address', o.delivery_address,
      'created_at', o.created_at,
      'updated_at', o.updated_at,
      'delivery_latitude', o.delivery_latitude,
      'delivery_longitude', o.delivery_longitude,
      'group_code', o.group_code,
      'scheduled_for', o.scheduled_for
    )
    FROM public.orders o
    WHERE o.id = v_order_id
  );
END;
$$;
REVOKE ALL ON FUNCTION public.create_order_transactional(UUID, TEXT, NUMERIC, NUMERIC, TEXT, JSONB, TIMESTAMPTZ, TEXT, NUMERIC, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_order_transactional(UUID, TEXT, NUMERIC, NUMERIC, TEXT, JSONB, TIMESTAMPTZ, TEXT, NUMERIC, NUMERIC) TO authenticated;
-- Policies for couriers table
ALTER TABLE public.couriers ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'couriers_select_all_authenticated' AND polrelid = 'public.couriers'::regclass) THEN
    CREATE POLICY couriers_select_all_authenticated ON public.couriers
      FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'couriers_upsert_own' AND polrelid = 'public.couriers'::regclass) THEN
    CREATE POLICY couriers_upsert_own ON public.couriers
      FOR ALL TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'couriers_service_all' AND polrelid = 'public.couriers'::regclass) THEN
    CREATE POLICY couriers_service_all ON public.couriers
      FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
END $$;
DROP TRIGGER IF EXISTS trg_couriers_touch_updated_at ON public.couriers;
CREATE TRIGGER trg_couriers_touch_updated_at
BEFORE UPDATE ON public.couriers
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
DROP TRIGGER IF EXISTS trg_restaurants_touch_updated_at ON public.restaurants;
CREATE TRIGGER trg_restaurants_touch_updated_at
BEFORE UPDATE ON public.restaurants
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
DROP TRIGGER IF EXISTS trg_menu_items_touch_updated_at ON public.menu_items;
CREATE TRIGGER trg_menu_items_touch_updated_at
BEFORE UPDATE ON public.menu_items
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
DROP TRIGGER IF EXISTS trg_wallets_touch_updated_at ON public.wallets;
CREATE TRIGGER trg_wallets_touch_updated_at
BEFORE UPDATE ON public.wallets
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
-- Production-grade seed for real test users
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
  v_order_active UUID := '47000000-0000-0000-0000-000000000001';
  v_order_ready UUID := '47000000-0000-0000-0000-000000000002';
  v_order_late UUID := '47000000-0000-0000-0000-000000000003';
  v_order_cancelled UUID := '47000000-0000-0000-0000-000000000004';
  v_order_reviewed UUID := '47000000-0000-0000-0000-000000000005';
BEGIN
  SELECT id INTO v_restaurant_owner_id FROM auth.users WHERE email = 'anis.justwork@gmail.com' LIMIT 1;
  SELECT id INTO v_client_id FROM auth.users WHERE email = 'anwarismael258@gmail.com' LIMIT 1;
  SELECT id INTO v_courier_id FROM auth.users WHERE email = 'youngmonster199@gmail.com' LIMIT 1;

  IF v_restaurant_owner_id IS NULL OR v_client_id IS NULL OR v_courier_id IS NULL THEN
    RAISE NOTICE 'Compat seed skipped: users not found.';
    RETURN;
  END IF;

  UPDATE public.profiles SET
    full_name = COALESCE(NULLIF(full_name, ''), 'Anwar Ismael'),
    phone = COALESCE(NULLIF(phone, ''), '+258877688695'),
    role = 'client',
    neighborhood = COALESCE(NULLIF(neighborhood, ''), 'Polana'),
    city = COALESCE(NULLIF(city, ''), 'Maputo'),
    preferred_payment_method = COALESCE(NULLIF(preferred_payment_method, ''), 'emola'),
    mobile_operator = COALESCE(NULLIF(mobile_operator, ''), 'movitel'),
    payment_contact = COALESCE(NULLIF(payment_contact, ''), '877688695')
  WHERE id = v_client_id OR user_id = v_client_id;

  UPDATE public.profiles SET
    full_name = COALESCE(NULLIF(full_name, ''), 'Deligo Biker'),
    phone = COALESCE(NULLIF(phone, ''), '+258841130015'),
    role = 'courier',
    kyc_status = 'approved',
    kyc_completed = TRUE,
    preferred_payment_method = COALESCE(NULLIF(preferred_payment_method, ''), 'm-pesa'),
    mobile_operator = COALESCE(NULLIF(mobile_operator, ''), 'vodacom'),
    payment_contact = COALESCE(NULLIF(payment_contact, ''), '841130015')
  WHERE id = v_courier_id OR user_id = v_courier_id;

  UPDATE public.profiles SET
    full_name = COALESCE(NULLIF(full_name, ''), 'Deligo Restaurante'),
    phone = COALESCE(NULLIF(phone, ''), '+258851709807'),
    role = 'restaurant',
    neighborhood = COALESCE(NULLIF(neighborhood, ''), 'Polana'),
    city = COALESCE(NULLIF(city, ''), 'Maputo'),
    preferred_payment_method = COALESCE(NULLIF(preferred_payment_method, ''), 'm-pesa'),
    mobile_operator = COALESCE(NULLIF(mobile_operator, ''), 'vodacom'),
    payment_contact = COALESCE(NULLIF(payment_contact, ''), '851709807')
  WHERE id = v_restaurant_owner_id OR user_id = v_restaurant_owner_id;

  INSERT INTO public.couriers (id, full_name, phone, current_latitude, current_longitude, is_online, rating, total_deliveries, earnings_today, acceptance_rate, cancellation_rate)
  VALUES (v_courier_id, 'Deligo Biker', '+258841130015', -25.9649, 32.5887, TRUE, 4.8, 42, 1200, 92, 3)
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    phone = EXCLUDED.phone,
    current_latitude = EXCLUDED.current_latitude,
    current_longitude = EXCLUDED.current_longitude,
    is_online = EXCLUDED.is_online,
    rating = EXCLUDED.rating,
    total_deliveries = EXCLUDED.total_deliveries,
    earnings_today = EXCLUDED.earnings_today,
    acceptance_rate = EXCLUDED.acceptance_rate,
    cancellation_rate = EXCLUDED.cancellation_rate,
    updated_at = NOW();

  SELECT id INTO v_restaurant_id FROM public.restaurants WHERE owner_id = v_restaurant_owner_id ORDER BY created_at ASC LIMIT 1;
  IF v_restaurant_id IS NULL THEN
    INSERT INTO public.restaurants (id, owner_id, name, description, phone, address, neighborhood, city, latitude, longitude, image_url, rating, is_open, opening_time, closing_time, estimated_delivery_time, wallet_balance, created_at, updated_at)
    VALUES (gen_random_uuid(), v_restaurant_owner_id, 'Deligo Restaurante', 'Restaurante urbano com pratos fortes, promos e entrega rapida em Maputo.', '+258851709807', 'Av. Julius Nyerere, Maputo', 'Polana', 'Maputo', -25.9645, 32.5880, 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80', 4.8, TRUE, '08:00', '23:00', 25, 18450, NOW(), NOW())
    RETURNING id INTO v_restaurant_id;
  ELSE
    UPDATE public.restaurants SET
      name = 'Deligo Restaurante',
      description = 'Restaurante urbano com pratos fortes, promos e entrega rapida em Maputo.',
      phone = '+258851709807',
      address = 'Av. Julius Nyerere, Maputo',
      neighborhood = 'Polana',
      city = 'Maputo',
      latitude = COALESCE(latitude, -25.9645),
      longitude = COALESCE(longitude, 32.5880),
      image_url = COALESCE(NULLIF(image_url, ''), 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80'),
      rating = 4.8,
      is_open = TRUE,
      opening_time = '08:00',
      closing_time = '23:00',
      estimated_delivery_time = 25,
      wallet_balance = 18450,
      updated_at = NOW()
    WHERE id = v_restaurant_id;
  END IF;

  INSERT INTO public.wallets (user_id, balance, currency, is_active, created_at, updated_at)
  VALUES
    (v_client_id, 1250, 'MZN', TRUE, NOW(), NOW()),
    (v_courier_id, 2350, 'MZN', TRUE, NOW(), NOW()),
    (v_restaurant_owner_id, 18450, 'MZN', TRUE, NOW(), NOW())
  ON CONFLICT (user_id) DO UPDATE SET
    balance = EXCLUDED.balance,
    currency = EXCLUDED.currency,
    is_active = TRUE,
    updated_at = NOW();

  INSERT INTO public.user_addresses (user_id, label, address, reference, delivery_instructions, neighborhood, city, latitude, longitude, is_default, created_at, updated_at)
  SELECT v_client_id, 'Casa', 'Av. Julius Nyerere, Maputo', 'Portao azul', 'Apartamento 203', 'Polana', 'Maputo', -25.9653, 32.5891, TRUE, NOW(), NOW()
  WHERE NOT EXISTS (SELECT 1 FROM public.user_addresses WHERE user_id = v_client_id AND is_default = TRUE);

  UPDATE public.user_addresses
  SET address = 'Av. Julius Nyerere, Maputo', reference = 'Portao azul', delivery_instructions = 'Apartamento 203', neighborhood = 'Polana', city = 'Maputo', latitude = -25.9653, longitude = 32.5891, is_default = TRUE, updated_at = NOW()
  WHERE user_id = v_client_id AND is_default = TRUE;

  INSERT INTO public.menu_items (restaurant_id, name, description, price, image_url, category, is_available, created_at, updated_at)
  SELECT v_restaurant_id, x.name, x.description, x.price, x.image_url, x.category, x.is_available, NOW(), NOW()
  FROM (VALUES
    ('Combo Almoco Deligo','Combo promocional com burger, batata e bebida.',650,'https://images.unsplash.com/photo-1561758033-d89a9ad46330?auto=format&fit=crop&w=1200&q=80','Promocoes',TRUE),
    ('Frango Grelhado Executivo','Frango grelhado com arroz e salada fresca.',780,'https://images.unsplash.com/photo-1604908176997-125f25cc6f3d?auto=format&fit=crop&w=1200&q=80','Pratos principais',TRUE),
    ('Burger Deligo','Burger artesanal com queijo, bacon e molho da casa.',480,'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=1200&q=80','Fast Food',TRUE),
    ('Batata Rustica Crocante','Batata rustica com ervas e molho especial.',220,'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?auto=format&fit=crop&w=1200&q=80','Acompanhamentos',FALSE),
    ('Coca-Cola 2L','Refrigerante gelado para acompanhar o pedido.',180,'https://images.unsplash.com/photo-1629203851122-3726ecdf080e?auto=format&fit=crop&w=1200&q=80','Bebidas',FALSE),
    ('Cheesecake de Morango','Sobremesa cremosa com cobertura de morango.',260,'https://images.unsplash.com/photo-1533134242443-d4fd215305ad?auto=format&fit=crop&w=1200&q=80','Sobremesas',FALSE),
    ('Tosta Mista da Casa','Lanche rapido com queijo e fiambre.',190,'https://images.unsplash.com/photo-1528735602780-2552fd46c7af?auto=format&fit=crop&w=1200&q=80','Pequeno-almoco / Lanches',FALSE),
    ('Wrap Light de Frango','Wrap leve com legumes crocantes e molho de iogurte.',390,'https://images.unsplash.com/photo-1608039755401-742074f0548d?auto=format&fit=crop&w=1200&q=80','Saudavel / Light',TRUE),
    ('Matapa Premium','Especialidade local servida com arroz aromatizado.',860,'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=1200&q=80','Especialidades',TRUE)
  ) AS x(name,description,price,image_url,category,is_available)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.menu_items m WHERE m.restaurant_id = v_restaurant_id AND m.name = x.name
  );

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

    INSERT INTO public.orders (id, client_id, customer_id, restaurant_id, courier_id, status, total_amount, total, payment_status, delivery_fee, admin_commission, delivery_address, delivery_latitude, delivery_longitude, confirmed_by_customer, created_at, updated_at)
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

    INSERT INTO public.payments (id, order_id, amount, payment_method, status, transaction_id, created_at, updated_at)
    VALUES
      (gen_random_uuid(), v_order_active, 1100, 'wallet', 'completed', 'PAY-DELIGO-ACTIVE', NOW() - interval '34 minutes', NOW() - interval '33 minutes'),
      (gen_random_uuid(), v_order_ready, 850, 'wallet', 'completed', 'PAY-DELIGO-READY', NOW() - interval '17 minutes', NOW() - interval '16 minutes'),
      (gen_random_uuid(), v_order_late, 990, 'wallet', 'completed', 'PAY-DELIGO-LATE', NOW() - interval '94 minutes', NOW() - interval '93 minutes'),
      (gen_random_uuid(), v_order_cancelled, 540, 'wallet', 'failed', 'PAY-DELIGO-CANCELLED', NOW() - interval '2 hours', NOW() - interval '111 minutes'),
      (gen_random_uuid(), v_order_reviewed, 1340, 'wallet', 'completed', 'PAY-DELIGO-REVIEW', NOW() - interval '1 day', NOW() - interval '1 day');

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
      RAISE NOTICE 'Compat production seed orders/messages/payments skipped: %', SQLERRM;
  END;
END $$;
COMMIT;
