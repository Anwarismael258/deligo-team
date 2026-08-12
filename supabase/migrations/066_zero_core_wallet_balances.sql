DO $$
DECLARE
  v_admin_id uuid := '2ef7f269-b36e-4903-ab2d-72b2a74ca28e';
  v_client_id uuid := '680a7827-68fe-49fa-b005-62e148a6e2b4';
  v_restaurant_owner_id uuid := 'feadf74b-2d43-4e65-ab13-afc02e5837a4';
  v_courier_id uuid := '8df3245f-39cd-4364-9649-50873599fc2c';
BEGIN
  UPDATE public.wallets
  SET
    balance = 0,
    updated_at = now()
  WHERE user_id IN (
    v_admin_id,
    v_client_id,
    v_restaurant_owner_id,
    v_courier_id
  );

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'restaurants'
      AND column_name = 'wallet_balance'
  ) THEN
    UPDATE public.restaurants
    SET wallet_balance = 0
    WHERE owner_id = v_restaurant_owner_id;
  END IF;
END $$;
