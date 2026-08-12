BEGIN;
ALTER TABLE IF EXISTS public.orders
  ADD COLUMN IF NOT EXISTS subtotal NUMERIC DEFAULT 0;
UPDATE public.orders
SET subtotal = GREATEST(
  COALESCE(subtotal, 0),
  COALESCE(total_amount, total, 0) - COALESCE(delivery_fee, 0)
)
WHERE subtotal IS NULL
   OR subtotal = 0;
CREATE OR REPLACE FUNCTION public.sync_order_compat_fields()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.client_id IS NULL AND NEW.customer_id IS NOT NULL THEN
    NEW.client_id = NEW.customer_id;
  END IF;
  IF NEW.customer_id IS NULL AND NEW.client_id IS NOT NULL THEN
    NEW.customer_id = NEW.client_id;
  END IF;

  IF NEW.total_amount IS NULL AND NEW.total IS NOT NULL THEN
    NEW.total_amount = NEW.total;
  END IF;
  IF NEW.total IS NULL AND NEW.total_amount IS NOT NULL THEN
    NEW.total = NEW.total_amount;
  END IF;

  IF NEW.total_amount IS NULL THEN NEW.total_amount = 0; END IF;
  IF NEW.total IS NULL THEN NEW.total = NEW.total_amount; END IF;
  IF NEW.delivery_fee IS NULL THEN NEW.delivery_fee = 0; END IF;
  IF NEW.subtotal IS NULL OR NEW.subtotal = 0 THEN
    NEW.subtotal = GREATEST(COALESCE(NEW.total_amount, NEW.total, 0) - COALESCE(NEW.delivery_fee, 0), 0);
  END IF;

  IF NEW.payment_status IS NULL OR NEW.payment_status = '' THEN
    NEW.payment_status = CASE
      WHEN NEW.status IN ('paid', 'accepted', 'preparing', 'ready', 'picked_up', 'delivering', 'in_transit', 'arrived', 'delivered', 'completed')
        THEN 'completed'
      WHEN NEW.status = 'cancelled'
        THEN 'failed'
      ELSE 'pending'
    END;
  END IF;

  IF NEW.admin_commission IS NULL THEN
    NEW.admin_commission = ROUND((COALESCE(NEW.total_amount, 0) * 0.15)::numeric, 2);
  END IF;
  IF NEW.updated_at IS NULL THEN NEW.updated_at = NOW(); END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
COMMIT;
