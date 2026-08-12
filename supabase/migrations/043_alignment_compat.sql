-- 043_alignment_compat.sql
-- Alignment migration: add missing columns, create compatibility tables/views used by app.

BEGIN;
-- 1) profiles: add columns expected by app (non-destructive)
DO $$
BEGIN
  IF to_regclass('public.profiles') IS NULL THEN
    RETURN;
  END IF;

  -- Basic identity columns used by app
  ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS full_name TEXT,
    ADD COLUMN IF NOT EXISTS phone TEXT,
    ADD COLUMN IF NOT EXISTS user_id UUID,
    ADD COLUMN IF NOT EXISTS kyc_status TEXT;

  -- Keep user_id in sync with id if null (avoid duplicate user_id)
  UPDATE public.profiles p
  SET user_id = p.id
  WHERE p.user_id IS NULL
    AND p.id IS NOT NULL
    AND p.id <> '00000000-0000-0000-0000-000000000000'::uuid
    AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p.id)
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles p2 WHERE p2.user_id = p.id
    );

  -- Backfill full_name from existing name if needed (only if name column exists)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'name'
  ) THEN
    UPDATE public.profiles
    SET full_name = name
    WHERE full_name IS NULL AND name IS NOT NULL;
  END IF;

  -- Backfill name from full_name if needed (only if name column exists)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'name'
  ) THEN
    UPDATE public.profiles
    SET name = full_name
    WHERE name IS NULL AND full_name IS NOT NULL;
  END IF;

  -- Default kyc_status for couriers
  UPDATE public.profiles
  SET kyc_status = COALESCE(kyc_status, 'pending')
  WHERE kyc_status IS NULL AND role = 'courier';

  -- Default kyc_status for non-couriers
  UPDATE public.profiles
  SET kyc_status = COALESCE(kyc_status, 'approved')
  WHERE kyc_status IS NULL AND role IN ('client','restaurant');
END $$;
-- 2) wallets: ensure user_id column exists (app expects wallets.user_id)
DO $$
BEGIN
  IF to_regclass('public.wallets') IS NOT NULL THEN
    ALTER TABLE public.wallets
      ADD COLUMN IF NOT EXISTS user_id UUID;
  END IF;
END $$;
-- 3) wallet_deposits: ensure table and columns exist
DO $$
BEGIN
  IF to_regclass('public.wallet_deposits') IS NULL THEN
    CREATE TABLE public.wallet_deposits (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      wallet_id UUID REFERENCES public.wallets(id) ON DELETE SET NULL,
      user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
      amount NUMERIC NOT NULL,
      payment_method TEXT,
      status TEXT DEFAULT 'pending',
      transaction_id TEXT,
      phone_number TEXT,
      reference TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  ELSE
    ALTER TABLE public.wallet_deposits
      ADD COLUMN IF NOT EXISTS wallet_id UUID,
      ADD COLUMN IF NOT EXISTS user_id UUID,
      ADD COLUMN IF NOT EXISTS amount NUMERIC,
      ADD COLUMN IF NOT EXISTS payment_method TEXT,
      ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending',
      ADD COLUMN IF NOT EXISTS transaction_id TEXT,
      ADD COLUMN IF NOT EXISTS phone_number TEXT,
      ADD COLUMN IF NOT EXISTS reference TEXT,
      ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now(),
      ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();
  END IF;
END $$;
-- 4) withdrawal_requests: create if missing
DO $$
BEGIN
  IF to_regclass('public.withdrawal_requests') IS NULL THEN
    CREATE TABLE public.withdrawal_requests (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
      amount NUMERIC NOT NULL,
      method TEXT,
      status TEXT DEFAULT 'pending',
      notes TEXT,
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  END IF;
END $$;
-- Ensure RLS policies for withdrawal_requests
DO $$
BEGIN
  IF to_regclass('public.withdrawal_requests') IS NULL THEN RETURN; END IF;
  ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY;
  CREATE POLICY withdrawal_requests_select_own ON public.withdrawal_requests
    FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
  CREATE POLICY withdrawal_requests_insert_own ON public.withdrawal_requests
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id OR public.is_admin());
  CREATE POLICY withdrawal_requests_update_own ON public.withdrawal_requests
    FOR UPDATE TO authenticated USING (auth.uid() = user_id OR public.is_admin())
    WITH CHECK (auth.uid() = user_id OR public.is_admin());
  CREATE POLICY withdrawal_requests_service_all ON public.withdrawal_requests
    FOR ALL TO service_role USING (true) WITH CHECK (true);
END $$;
-- 5) couriers: compatibility view for app if table doesn't exist
DO $$
BEGIN
  IF to_regclass('public.couriers') IS NULL THEN
    IF to_regclass('public.profiles') IS NOT NULL THEN
      EXECUTE $view$
        CREATE OR REPLACE VIEW public.couriers AS
        SELECT
          id,
          COALESCE(full_name, name, '') AS full_name,
          phone,
          role,
          created_at,
          updated_at
        FROM public.profiles
        WHERE role = 'courier';
      $view$;
    END IF;
  END IF;
END $$;
COMMIT;
