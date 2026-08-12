-- Deligo: inventory metadata for menu items + wallet/profile compat

ALTER TABLE IF EXISTS public.menu_items
  ADD COLUMN IF NOT EXISTS stock_quantity INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS item_rating NUMERIC(3,2) DEFAULT 4.6,
  ADD COLUMN IF NOT EXISTS prep_time_minutes INTEGER DEFAULT 25;
UPDATE public.menu_items
SET
  stock_quantity = COALESCE(stock_quantity, CASE WHEN COALESCE(is_available, true) THEN 12 ELSE 0 END),
  item_rating = COALESCE(item_rating, 4.6),
  prep_time_minutes = COALESCE(prep_time_minutes, 25),
  is_available = CASE
    WHEN COALESCE(stock_quantity, CASE WHEN COALESCE(is_available, true) THEN 12 ELSE 0 END) <= 0 THEN FALSE
    ELSE COALESCE(is_available, TRUE)
  END
WHERE TRUE;
ALTER TABLE IF EXISTS public.profiles
  ADD COLUMN IF NOT EXISTS preferred_payment_method TEXT,
  ADD COLUMN IF NOT EXISTS payment_contact TEXT,
  ADD COLUMN IF NOT EXISTS mobile_operator TEXT;
UPDATE public.profiles
SET
  preferred_payment_method = COALESCE(preferred_payment_method, CASE
    WHEN phone LIKE '84%' OR phone LIKE '85%' OR phone LIKE '+25884%' OR phone LIKE '+25885%' THEN 'm-pesa'
    WHEN phone LIKE '86%' OR phone LIKE '87%' OR phone LIKE '+25886%' OR phone LIKE '+25887%' THEN 'emola'
    ELSE preferred_payment_method
  END),
  payment_contact = COALESCE(payment_contact, phone),
  mobile_operator = COALESCE(mobile_operator, CASE
    WHEN phone LIKE '84%' OR phone LIKE '85%' OR phone LIKE '+25884%' OR phone LIKE '+25885%' THEN 'vodacom'
    WHEN phone LIKE '86%' OR phone LIKE '87%' OR phone LIKE '+25886%' OR phone LIKE '+25887%' THEN 'movitel'
    ELSE mobile_operator
  END)
WHERE TRUE;
