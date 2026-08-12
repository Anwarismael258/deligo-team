BEGIN;
DO $$
DECLARE
  v_anwar_id UUID;
  v_admin_id UUID;
  v_keep_ids UUID[];
  v_bad_user_ids UUID[];
  v_bad_restaurant_ids UUID[] := ARRAY[]::UUID[];
  v_bad_order_ids UUID[] := ARRAY[]::UUID[];
  v_has_available_balance BOOLEAN := FALSE;
  v_has_pending_balance BOOLEAN := FALSE;
  v_has_locked_balance BOOLEAN := FALSE;
  rec RECORD;
BEGIN
  SELECT id
  INTO v_anwar_id
  FROM auth.users
  WHERE LOWER(email) = 'anwarismael258@gmail.com'
     OR phone IN ('+258877688694', '877688694', '+258877688695', '877688695')
  ORDER BY created_at ASC
  LIMIT 1;

  SELECT id
  INTO v_admin_id
  FROM auth.users
  WHERE LOWER(email) = 'deligoentregas@gmail.com'
     OR phone IN ('+258841130015', '841130015')
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_anwar_id IS NULL THEN
    RAISE EXCEPTION 'Conta do Anwar nao encontrada para o reset final.';
  END IF;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Conta do Deligo CEO nao encontrada para o reset final.';
  END IF;

  v_keep_ids := ARRAY[v_anwar_id, v_admin_id]::UUID[];

  SELECT COALESCE(array_agg(id), ARRAY[]::UUID[])
  INTO v_bad_user_ids
  FROM auth.users
  WHERE id <> ALL (v_keep_ids);

  IF to_regclass('public.restaurants') IS NOT NULL THEN
    SELECT COALESCE(array_agg(id), ARRAY[]::UUID[])
    INTO v_bad_restaurant_ids
    FROM public.restaurants
    WHERE owner_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.orders') IS NOT NULL THEN
    SELECT COALESCE(array_agg(id), ARRAY[]::UUID[])
    INTO v_bad_order_ids
    FROM public.orders
    WHERE restaurant_id = ANY(v_bad_restaurant_ids)
       OR COALESCE(client_id, customer_id) = ANY(v_bad_user_ids)
       OR courier_id = ANY(v_bad_user_ids);
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
      AND c.column_name IN (
        'user_id',
        'owner_id',
        'sender_id',
        'receiver_id',
        'reviewer_id',
        'reporter_id',
        'reported_user_id',
        'referrer_id',
        'referee_id',
        'referrer_user_id',
        'referee_user_id',
        'recipient_id',
        'actor_id',
        'client_id',
        'customer_id',
        'courier_id'
      )
      AND c.table_name NOT IN ('wallets', 'restaurants', 'orders')
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
      AND c.column_name = 'order_id'
  LOOP
    EXECUTE format(
      'DELETE FROM public.%I WHERE %I = ANY ($1)',
      rec.table_name,
      rec.column_name
    )
    USING v_bad_order_ids;
  END LOOP;

  IF to_regclass('public.deliveries') IS NOT NULL THEN
    DELETE FROM public.deliveries
    WHERE order_id = ANY(v_bad_order_ids)
       OR courier_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.menu_items') IS NOT NULL THEN
    DELETE FROM public.menu_items
    WHERE restaurant_id = ANY(v_bad_restaurant_ids);
  END IF;

  IF to_regclass('public.orders') IS NOT NULL THEN
    DELETE FROM public.orders
    WHERE id = ANY(v_bad_order_ids)
       OR restaurant_id = ANY(v_bad_restaurant_ids)
       OR COALESCE(client_id, customer_id) = ANY(v_bad_user_ids)
       OR courier_id = ANY(v_bad_user_ids);
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

  IF to_regclass('public.wallet_deposits') IS NOT NULL THEN
    DELETE FROM public.wallet_deposits
    WHERE user_id = ANY(v_bad_user_ids)
       OR wallet_id IN (
         SELECT id FROM public.wallets WHERE user_id = ANY(v_bad_user_ids)
       );
  END IF;

  IF to_regclass('public.wallet_ledger') IS NOT NULL THEN
    DELETE FROM public.wallet_ledger
    WHERE user_id = ANY(v_bad_user_ids)
       OR wallet_id IN (
         SELECT id FROM public.wallets WHERE user_id = ANY(v_bad_user_ids)
       );
  END IF;

  IF to_regclass('public.wallets') IS NOT NULL THEN
    DELETE FROM public.wallets
    WHERE user_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.notifications') IS NOT NULL THEN
    DELETE FROM public.notifications
    WHERE user_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.push_notifications') IS NOT NULL THEN
    DELETE FROM public.push_notifications
    WHERE user_id = ANY(v_bad_user_ids);
  END IF;

  IF to_regclass('public.profiles') IS NOT NULL THEN
    DELETE FROM public.profiles
    WHERE id = ANY(v_bad_user_ids);
  END IF;

  DELETE FROM auth.users
  WHERE id = ANY(v_bad_user_ids);

  IF NOT EXISTS (SELECT 1 FROM public.wallets WHERE user_id = v_anwar_id) THEN
    INSERT INTO public.wallets (user_id, balance, currency, is_active, created_at, updated_at)
    VALUES (v_anwar_id, 123.50, 'MZN', TRUE, NOW(), NOW());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.wallets WHERE user_id = v_admin_id) THEN
    INSERT INTO public.wallets (user_id, balance, currency, is_active, created_at, updated_at)
    VALUES (v_admin_id, 0, 'MZN', TRUE, NOW(), NOW());
  END IF;

  UPDATE public.wallets
  SET
    balance = CASE
      WHEN user_id = v_anwar_id THEN 123.50
      WHEN user_id = v_admin_id THEN 0
      ELSE balance
    END,
    is_active = TRUE,
    updated_at = NOW()
  WHERE user_id IN (v_anwar_id, v_admin_id);

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'wallets'
      AND column_name = 'available_balance'
  )
  INTO v_has_available_balance;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'wallets'
      AND column_name = 'pending_balance'
  )
  INTO v_has_pending_balance;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'wallets'
      AND column_name = 'locked_balance'
  )
  INTO v_has_locked_balance;

  IF v_has_available_balance THEN
    UPDATE public.wallets
    SET available_balance = CASE
      WHEN user_id = v_anwar_id THEN 123.50
      WHEN user_id = v_admin_id THEN 0
      ELSE available_balance
    END
    WHERE user_id IN (v_anwar_id, v_admin_id);
  END IF;

  IF v_has_pending_balance THEN
    UPDATE public.wallets
    SET pending_balance = 0
    WHERE user_id IN (v_anwar_id, v_admin_id);
  END IF;

  IF v_has_locked_balance THEN
    UPDATE public.wallets
    SET locked_balance = 0
    WHERE user_id IN (v_anwar_id, v_admin_id);
  END IF;
END $$;
COMMIT;
