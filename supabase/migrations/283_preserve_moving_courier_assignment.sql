BEGIN;
CREATE OR REPLACE FUNCTION public.preserve_recent_courier_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.courier_id IS NOT NULL
     AND NEW.courier_id IS NULL
     AND NEW.status = 'ready'
     AND EXISTS (
       SELECT 1
       FROM public.deliveries d
       WHERE d.order_id = OLD.id
         AND d.courier_id = OLD.courier_id
         AND d.updated_at >= NOW() - INTERVAL '2 minutes'
     ) THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_preserve_recent_courier_assignment
  ON public.orders;
CREATE TRIGGER trg_preserve_recent_courier_assignment
BEFORE UPDATE OF courier_id, status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.preserve_recent_courier_assignment();
COMMIT;
