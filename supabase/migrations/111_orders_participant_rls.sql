BEGIN;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS orders_select_participants ON public.orders;
CREATE POLICY orders_select_participants
  ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = client_id
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
DROP POLICY IF EXISTS orders_update_restaurant_owner ON public.orders;
CREATE POLICY orders_update_restaurant_owner
  ON public.orders
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.restaurants r
      WHERE r.id = orders.restaurant_id
        AND r.owner_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.restaurants r
      WHERE r.id = orders.restaurant_id
        AND r.owner_id = auth.uid()
    )
  );
DROP POLICY IF EXISTS orders_update_assigned_courier ON public.orders;
CREATE POLICY orders_update_assigned_courier
  ON public.orders
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = courier_id)
  WITH CHECK (auth.uid() = courier_id);
GRANT SELECT, UPDATE ON public.orders TO authenticated;
COMMIT;
