BEGIN;
ALTER TABLE public.payment_splits
  DROP CONSTRAINT IF EXISTS payment_splits_status_check;
ALTER TABLE public.payment_splits
  ADD CONSTRAINT payment_splits_status_check
  CHECK (
    status IN (
      'pending',
      'escrowed',
      'restaurant_confirmed',
      'completed',
      'failed',
      'cancelled'
    )
  );
COMMIT;
