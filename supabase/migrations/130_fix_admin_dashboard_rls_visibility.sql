BEGIN;
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_jwt_role text;
  v_profile_role text;
BEGIN
  IF auth.role() = 'service_role' THEN
    RETURN true;
  END IF;

  v_jwt_role := COALESCE(
    auth.jwt() ->> 'role',
    auth.jwt() -> 'app_metadata' ->> 'role',
    auth.jwt() -> 'user_metadata' ->> 'role'
  );

  IF v_jwt_role = 'admin' THEN
    RETURN true;
  END IF;

  SELECT p.role
    INTO v_profile_role
  FROM public.profiles p
  WHERE p.id = auth.uid()
  LIMIT 1;

  RETURN COALESCE(v_profile_role, '') = 'admin';
END;
$$;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO service_role;
DO $$
BEGIN
  IF to_regclass('public.wallets') IS NOT NULL THEN
    DROP POLICY IF EXISTS wallets_select_own ON public.wallets;
    DROP POLICY IF EXISTS wallets_insert_own ON public.wallets;
    DROP POLICY IF EXISTS wallets_update_own ON public.wallets;
    DROP POLICY IF EXISTS wallets_no_delete ON public.wallets;
    DROP POLICY IF EXISTS wallets_service_all ON public.wallets;
    DROP POLICY IF EXISTS wallets_admin_read_all ON public.wallets;

    ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

    CREATE POLICY wallets_select_own ON public.wallets
      FOR SELECT TO authenticated
      USING (auth.uid() = user_id OR public.is_admin());

    CREATE POLICY wallets_insert_own ON public.wallets
      FOR INSERT TO authenticated
      WITH CHECK (auth.uid() = user_id OR public.is_admin());

    CREATE POLICY wallets_update_own ON public.wallets
      FOR UPDATE TO authenticated
      USING (auth.uid() = user_id OR public.is_admin())
      WITH CHECK (auth.uid() = user_id OR public.is_admin());

    CREATE POLICY wallets_no_delete ON public.wallets
      FOR DELETE TO authenticated
      USING (public.is_admin());

    CREATE POLICY wallets_service_all ON public.wallets
      FOR ALL TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
DO $$
BEGIN
  IF to_regclass('public.orders') IS NOT NULL THEN
    DROP POLICY IF EXISTS orders_select_participants ON public.orders;
    DROP POLICY IF EXISTS orders_select_participants_admin ON public.orders;

    CREATE POLICY orders_select_participants ON public.orders
      FOR SELECT TO authenticated
      USING (
        public.is_admin()
        OR auth.uid() = client_id
        OR auth.uid() = customer_id
        OR auth.uid() = courier_id
        OR EXISTS (
          SELECT 1
          FROM public.restaurants r
          WHERE r.id = orders.restaurant_id
            AND r.owner_id = auth.uid()
        )
        OR (
          courier_id IS NULL
          AND status IN ('accepted', 'ready')
          AND EXISTS (
            SELECT 1
            FROM public.couriers c
            WHERE c.id = auth.uid()
              AND COALESCE(c.is_suspended, false) = false
          )
        )
      );
  END IF;
END $$;
COMMIT;
