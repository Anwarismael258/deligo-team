ALTER TABLE IF EXISTS public.orders
  ADD COLUMN IF NOT EXISTS combo_id UUID REFERENCES public.daily_combos(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS combo_title TEXT,
  ADD COLUMN IF NOT EXISTS combo_discount_percentage NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS combo_discount_amount NUMERIC(12,2) DEFAULT 0;
