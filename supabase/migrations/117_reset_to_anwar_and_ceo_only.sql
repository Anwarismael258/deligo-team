BEGIN;
DO $$
DECLARE
  v_anwar_id UUID;
  v_admin_id UUID;
  v_user_id UUID;
  v_primary_wallet UUID;
  v_has_available_balance BOOLEAN;
  v_has_pending_balance BOOLEAN;
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

  IF v_anwar_id IS NULL THEN
    RAISE EXCEPTION 'Conta do Anwar não encontrada em auth.users.';
  END IF;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Conta do Deligo CEO não encontrada em auth.users.';
  END IF;

  -- Limpeza preventiva de tabelas públicas que podem não cascadar sozinhas.
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
        'recipient_id'
      )
      AND c.table_name NOT IN ('wallets', 'restaurants')
  LOOP
    EXECUTE format(
      'DELETE FROM public.%I WHERE %I IS NOT NULL AND %I <> ALL ($1)',
      rec.table_name,
      rec.column_name,
      rec.column_name
    )
    USING ARRAY[v_anwar_id, v_admin_id]::UUID[];
  END LOOP;

  IF to_regclass('public.deliveries') IS NOT NULL THEN
    EXECUTE 'TRUNCATE TABLE public.deliveries CASCADE';
  END IF;

  IF to_regclass('public.couriers') IS NOT NULL THEN
    DELETE FROM public.couriers
    WHERE id <> ALL (ARRAY[v_anwar_id, v_admin_id]::UUID[]);
  END IF;

  IF to_regclass('public.orders') IS NOT NULL THEN
    IF to_regclass('public.restaurants') IS NOT NULL THEN
      UPDATE public.orders
      SET restaurant_id = NULL
      WHERE restaurant_id IN (
        SELECT id
        FROM public.restaurants
        WHERE owner_id <> ALL (ARRAY[v_anwar_id, v_admin_id]::UUID[])
      );
    END IF;
    EXECUTE 'TRUNCATE TABLE public.orders CASCADE';
  END IF;

  IF to_regclass('public.restaurants') IS NOT NULL THEN
    DELETE FROM public.restaurants
    WHERE owner_id <> ALL (ARRAY[v_anwar_id, v_admin_id]::UUID[]);
  END IF;

  IF to_regclass('public.wallet_deposits') IS NOT NULL THEN
    DELETE FROM public.wallet_deposits
    WHERE wallet_id IN (
      SELECT id
      FROM public.wallets
      WHERE user_id <> ALL (ARRAY[v_anwar_id, v_admin_id]::UUID[])
    );
  END IF;

  IF to_regclass('public.wallet_ledger') IS NOT NULL THEN
    DELETE FROM public.wallet_ledger
    WHERE wallet_id IN (
      SELECT id
      FROM public.wallets
      WHERE user_id <> ALL (ARRAY[v_anwar_id, v_admin_id]::UUID[])
    );
  END IF;

  IF to_regclass('public.wallets') IS NOT NULL THEN
    DELETE FROM public.wallets
    WHERE user_id <> ALL (ARRAY[v_anwar_id, v_admin_id]::UUID[]);
  END IF;

  -- Remove todas as outras contas e deixa o banco apenas com Anwar e Deligo CEO.
  DELETE FROM auth.users
  WHERE id <> ALL (ARRAY[v_anwar_id, v_admin_id]::UUID[]);

  -- Segunda passada para lixo órfão em tabelas sem FK forte.
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
        'recipient_id'
      )
      AND c.table_name NOT IN ('wallets', 'restaurants')
  LOOP
    EXECUTE format(
      'DELETE FROM public.%I WHERE %I IS NOT NULL AND %I <> ALL ($1)',
      rec.table_name,
      rec.column_name,
      rec.column_name
    )
    USING ARRAY[v_anwar_id, v_admin_id]::UUID[];
  END LOOP;

  -- Consolidar duplicadas das duas contas preservadas.
  IF to_regclass('public.wallets') IS NOT NULL THEN
    FOR v_user_id IN
      SELECT user_id
      FROM public.wallets
      WHERE user_id IN (v_anwar_id, v_admin_id)
      GROUP BY user_id
      HAVING COUNT(*) > 1
    LOOP
      SELECT id
      INTO v_primary_wallet
      FROM public.wallets
      WHERE user_id = v_user_id
      ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST, id DESC
      LIMIT 1;

      IF to_regclass('public.wallet_deposits') IS NOT NULL THEN
        UPDATE public.wallet_deposits
        SET wallet_id = v_primary_wallet
        WHERE wallet_id IN (
          SELECT id FROM public.wallets WHERE user_id = v_user_id AND id <> v_primary_wallet
        );
      END IF;

      IF to_regclass('public.wallet_ledger') IS NOT NULL THEN
        UPDATE public.wallet_ledger
        SET wallet_id = v_primary_wallet
        WHERE wallet_id IN (
          SELECT id FROM public.wallets WHERE user_id = v_user_id AND id <> v_primary_wallet
        );
      END IF;

      DELETE FROM public.wallets
      WHERE user_id = v_user_id
        AND id <> v_primary_wallet;
    END LOOP;
  END IF;

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
END $$;
COMMIT;
