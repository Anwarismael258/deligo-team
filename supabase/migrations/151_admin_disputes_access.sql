-- Allow admins to view order disputes
ALTER TABLE public.order_disputes ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'order_disputes_select_admin'
      AND polrelid = 'public.order_disputes'::regclass
  ) THEN
    CREATE POLICY order_disputes_select_admin
      ON public.order_disputes
      FOR SELECT
      TO authenticated
      USING (public.is_admin());
  END IF;
END $$;
