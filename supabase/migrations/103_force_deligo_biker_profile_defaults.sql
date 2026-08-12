DO $$
DECLARE
  v_courier_id UUID;
BEGIN
  SELECT id
  INTO v_courier_id
  FROM auth.users
  WHERE email = 'youngmonster199@gmail.com'
  LIMIT 1;

  IF v_courier_id IS NULL THEN
    RAISE NOTICE 'Courier user not found for Deligo Biker defaults.';
    RETURN;
  END IF;

  UPDATE public.profiles
  SET
    full_name = 'Deligo Biker',
    role = 'courier',
    phone = '+258841130015',
    preferred_payment_method = 'm-pesa',
    payment_contact = '841130015',
    mobile_operator = 'vodacom',
    city = COALESCE(NULLIF(city, ''), 'Maputo'),
    neighborhood = COALESCE(NULLIF(neighborhood, ''), 'Coop'),
    kyc_status = 'approved',
    kyc_completed = TRUE,
    updated_at = NOW()
  WHERE id = v_courier_id;

  UPDATE public.couriers
  SET
    full_name = 'Deligo Biker',
    phone = '+258841130015',
    is_online = TRUE,
    updated_at = NOW()
  WHERE id = v_courier_id;
END $$;
