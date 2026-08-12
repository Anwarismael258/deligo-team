BEGIN;
ALTER TABLE IF EXISTS public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.favorites ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF to_regclass('public.restaurants') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'restaurants' AND policyname = 'restaurants_public_read'
  ) THEN
    CREATE POLICY restaurants_public_read
      ON public.restaurants
      FOR SELECT
      TO authenticated, anon
      USING (COALESCE(is_open, true) = true);
  END IF;
END $$;
DO $$
BEGIN
  IF to_regclass('public.menu_items') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'menu_items' AND policyname = 'menu_items_public_read'
  ) THEN
    CREATE POLICY menu_items_public_read
      ON public.menu_items
      FOR SELECT
      TO authenticated, anon
      USING (COALESCE(is_available, true) = true);
  END IF;
END $$;
DO $$
BEGIN
  IF to_regclass('public.menu_items') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'menu_items' AND policyname = 'menu_items_owner_full_access'
  ) THEN
    CREATE POLICY menu_items_owner_full_access
      ON public.menu_items
      FOR ALL
      TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.restaurants r
          WHERE r.id = menu_items.restaurant_id
            AND r.owner_id = auth.uid()
        )
        OR public.is_admin()
      )
      WITH CHECK (
        EXISTS (
          SELECT 1
          FROM public.restaurants r
          WHERE r.id = menu_items.restaurant_id
            AND r.owner_id = auth.uid()
        )
        OR public.is_admin()
      );
  END IF;
END $$;
DO $$
BEGIN
  IF to_regclass('public.reviews') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'reviews' AND policyname = 'reviews_public_read'
  ) THEN
    CREATE POLICY reviews_public_read
      ON public.reviews
      FOR SELECT
      TO authenticated, anon
      USING (true);
  END IF;
END $$;
DO $$
BEGIN
  IF to_regclass('public.reviews') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'reviews' AND policyname = 'reviews_authenticated_insert'
  ) THEN
    CREATE POLICY reviews_authenticated_insert
      ON public.reviews
      FOR INSERT
      TO authenticated
      WITH CHECK (auth.uid() IS NOT NULL);
  END IF;
END $$;
DO $$
BEGIN
  IF to_regclass('public.favorites') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'favorites' AND policyname = 'favorites_select_own'
  ) THEN
    CREATE POLICY favorites_select_own
      ON public.favorites
      FOR SELECT
      TO authenticated
      USING (user_id = auth.uid() OR public.is_admin());
  END IF;
END $$;
DO $$
BEGIN
  IF to_regclass('public.favorites') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'favorites' AND policyname = 'favorites_insert_own'
  ) THEN
    CREATE POLICY favorites_insert_own
      ON public.favorites
      FOR INSERT
      TO authenticated
      WITH CHECK (user_id = auth.uid() OR public.is_admin());
  END IF;
END $$;
DO $$
BEGIN
  IF to_regclass('public.favorites') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'favorites' AND policyname = 'favorites_delete_own'
  ) THEN
    CREATE POLICY favorites_delete_own
      ON public.favorites
      FOR DELETE
      TO authenticated
      USING (user_id = auth.uid() OR public.is_admin());
  END IF;
END $$;
COMMIT;
