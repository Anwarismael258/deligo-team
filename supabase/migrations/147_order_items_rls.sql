-- Ensure order items visibility for participants
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS order_items_select_participants ON public.order_items;
CREATE POLICY order_items_select_participants
  ON public.order_items
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.id = order_items.order_id
        AND (
          o.client_id = auth.uid()
          OR o.customer_id = auth.uid()
          OR o.courier_id = auth.uid()
          OR EXISTS (
            SELECT 1
            FROM public.restaurants r
            WHERE r.id = o.restaurant_id
              AND r.owner_id = auth.uid()
          )
        )
    )
  );
DROP POLICY IF EXISTS order_items_service_all ON public.order_items;
CREATE POLICY order_items_service_all
  ON public.order_items
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
GRANT SELECT ON public.order_items TO authenticated;
