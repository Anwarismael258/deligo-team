-- Allow admins (custom role claim) to view all profiles
-- Requires auth.jwt() ->> 'role' = 'admin'

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND policyname = 'Admins can view all profiles'
  ) THEN
    EXECUTE 'CREATE POLICY "Admins can view all profiles" ON public.profiles
      FOR SELECT USING ((auth.jwt() ->> ''role'') = ''admin'')';
  END IF;
END;
$$;
