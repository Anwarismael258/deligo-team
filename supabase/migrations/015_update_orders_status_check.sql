-- Expand orders.status allowed values to support paid and courier flow.
-- Safe to run multiple times.

DO $$
DECLARE
  c_name text;
BEGIN
  SELECT conname
    INTO c_name
    FROM pg_constraint
   WHERE conrelid = 'public.orders'::regclass
     AND contype = 'c'
     AND pg_get_constraintdef(oid) ILIKE '%status%';

  IF c_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.orders DROP CONSTRAINT %I', c_name);
  END IF;
END;
$$;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
  CHECK (
    status IN (
      'pending',
      'paid',
      'accepted',
      'preparing',
      'ready',
      'courier_assigned',
      'on_the_way',
      'in_transit',
      'arrived',
      'delivered',
      'completed',
      'cancelled'
    )
  );
