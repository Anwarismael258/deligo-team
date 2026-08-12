BEGIN;
CREATE OR REPLACE FUNCTION public.sync_delivery_after_courier_unassignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.courier_id IS NOT NULL
     AND NEW.courier_id IS NULL
     AND NEW.status = 'ready' THEN
    UPDATE public.deliveries
    SET courier_id = NULL,
        status = 'pending',
        updated_at = NOW()
    WHERE order_id = NEW.id
      AND courier_id = OLD.courier_id;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_delivery_after_courier_unassignment
  ON public.orders;
CREATE TRIGGER trg_sync_delivery_after_courier_unassignment
AFTER UPDATE OF courier_id, status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.sync_delivery_after_courier_unassignment();
COMMIT;
