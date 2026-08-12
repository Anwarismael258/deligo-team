-- Allow authenticated users to create their own profile and wallet
-- Safe to run multiple times (idempotent)

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND policyname = 'Users can insert own profile'
  ) THEN
    EXECUTE 'CREATE POLICY "Users can insert own profile" ON public.profiles
      FOR INSERT WITH CHECK (auth.uid() = id)';
  END IF;
END;
$$;
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'wallets'
      AND policyname = 'Users can create own wallet'
  ) THEN
    EXECUTE 'CREATE POLICY "Users can create own wallet" ON public.wallets
      FOR INSERT WITH CHECK (auth.uid() = user_id)';
  END IF;
END;
$$;
-- Optional: allow users to update only their wallet metadata (not balance)
-- Balance updates should remain server-side; keep this disabled unless needed.;
