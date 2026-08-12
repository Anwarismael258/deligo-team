ALTER TABLE IF EXISTS public.orders
  ADD COLUMN IF NOT EXISTS inventory_applied_at timestamptz;
CREATE OR REPLACE FUNCTION public.apply_order_inventory_when_paid()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_item RECORD;
  v_new_stock integer;
BEGIN
  IF NEW.inventory_applied_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.status, '') NOT IN ('paid', 'accepted', 'preparing', 'ready', 'courier_assigned', 'in_transit', 'on_the_way', 'arrived', 'delivered', 'completed') THEN
    RETURN NEW;
  END IF;

  FOR v_item IN
    SELECT oi.menu_item_id, COALESCE(oi.quantity, 0) AS quantity
    FROM public.order_items oi
    WHERE oi.order_id = NEW.id
  LOOP
    UPDATE public.menu_items mi
    SET
      stock_quantity = GREATEST(COALESCE(mi.stock_quantity, 0) - v_item.quantity, 0),
      is_available = CASE
        WHEN GREATEST(COALESCE(mi.stock_quantity, 0) - v_item.quantity, 0) <= 0 THEN false
        ELSE true
      END,
      updated_at = NOW()
    WHERE mi.id = v_item.menu_item_id;
  END LOOP;

  NEW.inventory_applied_at = NOW();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_apply_order_inventory_when_paid ON public.orders;
CREATE TRIGGER trg_apply_order_inventory_when_paid
BEFORE UPDATE OF status ON public.orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION public.apply_order_inventory_when_paid();
