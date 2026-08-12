BEGIN;
DO $$
DECLARE
  v_anwar_id UUID;
  v_admin_id UUID;
  v_bad_user_ids UUID[];
  v_bad_restaurant_ids UUID[];
  v_bad_order_ids UUID[];
  rec RECORD;
BEGIN
  SELECT id
  INTO v_anwar_id
  FROM auth.users
  WHERE LOWER(email) = 'anwarismael258@gmail.com'
  LIMIT 1;

  SELECT id
  INTO v_admin_id
  FROM auth.users
  WHERE LOWER(email) = 'deligoentregas@gmail.com'
  LIMIT 1;

  IF v_anwar_id IS NULL OR v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Nao foi possivel localizar Anwar e Deligo CEO para o cleanup forcado.';
  END IF;

  SELECT COALESCE(array_agg(id), ARRAY[]::uuid[])
  INTO v_bad_user_ids
  FROM auth.users
  WHERE id <> ALL (ARRAY[v_anwar_id, v_admin_id]::uuid[]);

  IF to_regclass('public.restaurants') IS NOT NULL THEN
    SELECT COALESCE(array_agg(id), ARRAY[]::uuid[])
    INTO v_bad_restaurant_ids
    FROM public.restaurants
    WHERE owner_id <> ALL (ARRAY[v_anwar_id, v_admin_id]::uuid[]);
  ELSE
    v_bad_restaurant_ids := ARRAY[]::uuid[];
  END IF;

  IF to_regclass('public.orders') IS NOT NULL THEN
    SELECT COALESCE(array_agg(id), ARRAY[]::uuid[])
    INTO v_bad_order_ids
    FROM public.orders
    WHERE restaurant_id = ANY(v_bad_restaurant_ids)
       OR COALESCE(client_id, customer_id) = ANY(v_bad_user_ids)
       OR courier_id = ANY(v_bad_user_ids);
  ELSE
    v_bad_order_ids := ARRAY[]::uuid[];
  END IF;

  IF to_regclass('public.outbox_dispatches') IS NOT NULL THEN
    DELETE FROM public.outbox_dispatches
    WHERE restaurant_id = ANY(v_bad_restaurant_ids)
       OR order_id = ANY(v_bad_order_ids);
  END IF;

  FOR rec IN
    SELECT c.table_name, c.column_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema
     AND t.table_name = c.table_name
    WHERE c.table_schema = 'public'
      AND t.table_type = 'BASE TABLE'
      AND column_name IN (
        'user_id',
        'owner_id',
        'sender_id',
        'receiver_id',
        'reviewer_id',
        'reporter_id',
        'reported_user_id',
        'referrer_user_id',
        'referee_user_id',
        'recipient_id',
        'actor_id',
        'client_id',
        'customer_id',
        'courier_id'
      )
  LOOP
    EXECUTE format(
      'DELETE FROM public.%I WHERE %I = ANY ($1)',
      rec.table_name,
      rec.column_name
    )
    USING v_bad_user_ids;
  END LOOP;

  FOR rec IN
    SELECT c.table_name, c.column_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema
     AND t.table_name = c.table_name
    WHERE c.table_schema = 'public'
      AND t.table_type = 'BASE TABLE'
      AND column_name = 'order_id'
  LOOP
    EXECUTE format(
      'DELETE FROM public.%I WHERE %I = ANY ($1)',
      rec.table_name,
      rec.column_name
    )
    USING v_bad_order_ids;
  END LOOP;

  FOR rec IN
    SELECT c.table_name, c.column_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema
     AND t.table_name = c.table_name
    WHERE c.table_schema = 'public'
      AND t.table_type = 'BASE TABLE'
      AND c.column_name = 'restaurant_id'
      AND c.table_name <> 'orders'
  LOOP
    EXECUTE format(
      'DELETE FROM public.%I WHERE %I = ANY ($1)',
      rec.table_name,
      rec.column_name
    )
    USING v_bad_restaurant_ids;
  END LOOP;

  IF to_regclass('public.menu_items') IS NOT NULL THEN
    DELETE FROM public.menu_items
    WHERE restaurant_id = ANY(v_bad_restaurant_ids);
  END IF;

  IF to_regclass('public.deliveries') IS NOT NULL THEN
    DELETE FROM public.deliveries
    WHERE order_id = ANY(v_bad_order_ids)
       OR courier_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.orders') IS NOT NULL THEN
    UPDATE public.orders
    SET
      restaurant_id = CASE
        WHEN restaurant_id = ANY(v_bad_restaurant_ids) THEN NULL
        ELSE restaurant_id
      END,
      courier_id = CASE
        WHEN courier_id = ANY(v_bad_user_ids) THEN NULL
        ELSE courier_id
      END,
      client_id = CASE
        WHEN client_id = ANY(v_bad_user_ids) THEN NULL
        ELSE client_id
      END,
      customer_id = CASE
        WHEN customer_id = ANY(v_bad_user_ids) THEN NULL
        ELSE customer_id
      END
    WHERE restaurant_id = ANY(v_bad_restaurant_ids)
       OR courier_id = ANY(v_bad_user_ids)
       OR client_id = ANY(v_bad_user_ids)
       OR customer_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.restaurants') IS NOT NULL THEN
    DELETE FROM public.restaurants
    WHERE id = ANY(v_bad_restaurant_ids)
       OR owner_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.couriers') IS NOT NULL THEN
    DELETE FROM public.couriers
    WHERE id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.wallet_ledger') IS NOT NULL THEN
    DELETE FROM public.wallet_ledger
    WHERE user_id = ANY(v_bad_user_ids)
       OR order_id = ANY(v_bad_order_ids);
  END IF;

  IF to_regclass('public.wallet_deposits') IS NOT NULL THEN
    DELETE FROM public.wallet_deposits
    WHERE user_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.wallets') IS NOT NULL THEN
    DELETE FROM public.wallets
    WHERE user_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.profiles') IS NOT NULL THEN
    DELETE FROM public.profiles
    WHERE id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.users') IS NOT NULL THEN
    DELETE FROM public.users
    WHERE id = ANY(v_bad_user_ids);
  END IF;

  DELETE FROM auth.users
  WHERE id = ANY(v_bad_user_ids);
END $$;
COMMIT;
