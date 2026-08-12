BEGIN;
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_splits_order_id_unique
ON public.payment_splits(order_id);
COMMIT;
