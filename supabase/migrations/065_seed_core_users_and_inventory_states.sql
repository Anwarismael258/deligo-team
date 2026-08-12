DO $$
DECLARE
  v_admin_id uuid := '2ef7f269-b36e-4903-ab2d-72b2a74ca28e';
  v_client_id uuid := '680a7827-68fe-49fa-b005-62e148a6e2b4';
  v_restaurant_owner_id uuid := 'feadf74b-2d43-4e65-ab13-afc02e5837a4';
  v_courier_id uuid := '8df3245f-39cd-4364-9649-50873599fc2c';
  v_restaurant_id uuid;
BEGIN
  DELETE FROM public.profiles
  WHERE phone IN (
    '+258841130015',
    '+258877688695',
    '+258851709807',
    '+258835269961'
  )
  AND id NOT IN (v_admin_id, v_client_id, v_restaurant_owner_id, v_courier_id);

  INSERT INTO public.profiles (id, full_name, phone, role, avatar_url, address, kyc_status, updated_at)
  VALUES
    (v_admin_id, 'Deligo CEO', '+258841130015', 'admin', NULL, jsonb_build_object('address','Maputo, Mocambique'), 'approved', now()),
    (v_client_id, 'ANWAR', '+258877688695', 'customer', NULL, jsonb_build_object('address','25 de Setembro, Maputo'), 'approved', now()),
    (v_restaurant_owner_id, 'Deligo restaurante', '+258851709807', 'restaurant', NULL, jsonb_build_object('address','Bairro Coop, Maputo'), 'approved', now()),
    (v_courier_id, 'DELIGO BIKER', '+258835269961', 'courier', NULL, jsonb_build_object('address','Maputo, Mocambique'), 'approved', now())
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    phone = EXCLUDED.phone,
    role = EXCLUDED.role,
    address = EXCLUDED.address,
    kyc_status = EXCLUDED.kyc_status,
    updated_at = now();

  INSERT INTO public.user_addresses (
    user_id, label, address, neighborhood, city, is_default
  )
  VALUES
    (v_client_id, 'Casa', '25 de Setembro, Maputo', 'Central', 'Maputo', true),
    (v_restaurant_owner_id, 'Restaurante', 'Bairro Coop, Maputo', 'Coop', 'Maputo', true),
    (v_courier_id, 'Base', 'Maputo, Mocambique', 'Central', 'Maputo', true)
  ON CONFLICT DO NOTHING;

  INSERT INTO public.wallets (user_id, balance, currency, is_active, updated_at)
  VALUES
    (v_admin_id, COALESCE((SELECT balance FROM public.wallets WHERE user_id = v_admin_id LIMIT 1), 0), 'MZN', true, now()),
    (v_client_id, COALESCE((SELECT balance FROM public.wallets WHERE user_id = v_client_id LIMIT 1), 0), 'MZN', true, now()),
    (v_restaurant_owner_id, COALESCE((SELECT balance FROM public.wallets WHERE user_id = v_restaurant_owner_id LIMIT 1), 0), 'MZN', true, now()),
    (v_courier_id, COALESCE((SELECT balance FROM public.wallets WHERE user_id = v_courier_id LIMIT 1), 0), 'MZN', true, now())
  ON CONFLICT (user_id) DO UPDATE SET
    currency = 'MZN',
    is_active = true,
    updated_at = now();

  INSERT INTO public.couriers (id, full_name, phone, vehicle_type, is_online)
  VALUES (
    v_courier_id,
    'DELIGO BIKER',
    '+258835269961',
    'moto',
    true
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    phone = EXCLUDED.phone,
    vehicle_type = EXCLUDED.vehicle_type,
    is_online = EXCLUDED.is_online;

  SELECT id INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_restaurant_owner_id
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1;

  IF v_restaurant_id IS NOT NULL THEN
    UPDATE public.restaurants
    SET
      name = 'Deligo Restaurante',
      phone = '851709807',
      address = 'Bairro Coop, Maputo',
      neighborhood = 'Coop',
      city = 'Maputo',
      is_open = true,
      opening_time = '08:00',
      closing_time = '22:00',
      estimated_delivery_time = 35
    WHERE id = v_restaurant_id;

    UPDATE public.menu_items
    SET
      stock_quantity = CASE
        WHEN name = 'Burger Deligo Especial' THEN 5
        WHEN name = 'Frango Grelhado com Arroz' THEN 8
        WHEN name = 'Combo Shawarma + Batata + Refri' THEN 0
        WHEN name = 'Mousse de Chocolate Premium' THEN 0
        ELSE stock_quantity
      END,
      is_available = CASE
        WHEN name IN ('Combo Shawarma + Batata + Refri', 'Mousse de Chocolate Premium') THEN false
        ELSE true
      END
    WHERE restaurant_id = v_restaurant_id
      AND name IN (
        'Burger Deligo Especial',
        'Frango Grelhado com Arroz',
        'Combo Shawarma + Batata + Refri',
        'Mousse de Chocolate Premium'
      );
  END IF;
END $$;
