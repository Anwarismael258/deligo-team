DO $$
DECLARE
  v_client_id uuid;
  v_restaurant_id uuid;
BEGIN
  SELECT id INTO v_client_id
  FROM auth.users
  WHERE email = 'anwarismael258@gmail.com'
  LIMIT 1;

  SELECT r.id INTO v_restaurant_id
  FROM public.restaurants r
  JOIN auth.users u ON u.id = r.owner_id
  WHERE u.email = 'anis.justwork@gmail.com'
  ORDER BY r.created_at ASC NULLS LAST
  LIMIT 1;

  IF v_client_id IS NULL OR v_restaurant_id IS NULL THEN
    RAISE NOTICE 'Cliente ou restaurante nao encontrado para seed de favorito';
    RETURN;
  END IF;

  UPDATE public.menu_items
  SET
    is_available = true,
    stock_quantity = CASE
      WHEN COALESCE(stock_quantity, 0) <= 0 THEN 8
      ELSE stock_quantity
    END
  WHERE restaurant_id = v_restaurant_id;

  INSERT INTO public.favorites (user_id, restaurant_id)
  SELECT v_client_id, v_restaurant_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.favorites f
    WHERE f.user_id = v_client_id
      AND f.restaurant_id = v_restaurant_id
  );
END $$;
