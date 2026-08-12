ALTER TABLE IF EXISTS public.restaurants
  ADD COLUMN IF NOT EXISTS category TEXT,
  ADD COLUMN IF NOT EXISTS landmark_reference TEXT,
  ADD COLUMN IF NOT EXISTS price_range TEXT DEFAULT '$$',
  ADD COLUMN IF NOT EXISTS payment_wallet_number TEXT;
DO $$
BEGIN
  UPDATE public.restaurants
  SET
    category = COALESCE(NULLIF(category, ''), 'Restaurante'),
    landmark_reference = COALESCE(NULLIF(landmark_reference, ''), 'Próximo ao Polana Shopping'),
    price_range = COALESCE(NULLIF(price_range, ''), '$' || '$'),
    payment_wallet_number = COALESCE(NULLIF(payment_wallet_number, ''), phone);
END $$;
