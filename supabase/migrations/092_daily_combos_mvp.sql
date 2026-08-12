CREATE TABLE IF NOT EXISTS public.daily_combos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  discount_percentage NUMERIC(5,2) NOT NULL CHECK (discount_percentage > 0 AND discount_percentage <= 50),
  start_date TIMESTAMPTZ NOT NULL,
  end_date TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT daily_combos_dates_check CHECK (end_date > start_date)
);
CREATE UNIQUE INDEX IF NOT EXISTS daily_combos_one_active_per_restaurant_idx
  ON public.daily_combos (restaurant_id)
  WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS daily_combos_restaurant_idx
  ON public.daily_combos (restaurant_id, start_date, end_date);
ALTER TABLE public.daily_combos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "daily_combos_public_read_active" ON public.daily_combos;
CREATE POLICY "daily_combos_public_read_active"
ON public.daily_combos
FOR SELECT
TO authenticated
USING (is_active = TRUE);
DROP POLICY IF EXISTS "daily_combos_restaurant_manage" ON public.daily_combos;
CREATE POLICY "daily_combos_restaurant_manage"
ON public.daily_combos
FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.restaurants r
    WHERE r.id = daily_combos.restaurant_id
      AND r.owner_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.restaurants r
    WHERE r.id = daily_combos.restaurant_id
      AND r.owner_id = auth.uid()
  )
);
CREATE OR REPLACE FUNCTION public.set_daily_combos_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_daily_combos_updated_at ON public.daily_combos;
CREATE TRIGGER trg_daily_combos_updated_at
BEFORE UPDATE ON public.daily_combos
FOR EACH ROW
EXECUTE FUNCTION public.set_daily_combos_updated_at();
CREATE OR REPLACE FUNCTION public.deactivate_other_daily_combos()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.is_active = TRUE THEN
    UPDATE public.daily_combos
    SET is_active = FALSE,
        updated_at = NOW()
    WHERE restaurant_id = NEW.restaurant_id
      AND id <> NEW.id
      AND is_active = TRUE;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_daily_combos_deactivate_others ON public.daily_combos;
CREATE TRIGGER trg_daily_combos_deactivate_others
AFTER INSERT OR UPDATE OF is_active ON public.daily_combos
FOR EACH ROW
EXECUTE FUNCTION public.deactivate_other_daily_combos();
INSERT INTO public.daily_combos (
  restaurant_id,
  title,
  description,
  discount_percentage,
  start_date,
  end_date,
  is_active
)
SELECT
  r.id,
  'Combo do Dia',
  '20% OFF hoje no pedido do Deligo Restaurante.',
  20,
  NOW() - INTERVAL '2 hours',
  NOW() + INTERVAL '22 hours',
  TRUE
FROM public.restaurants r
JOIN auth.users u ON u.id = r.owner_id
WHERE u.email = 'anis.justwork@gmail.com'
  AND NOT EXISTS (
    SELECT 1
    FROM public.daily_combos dc
    WHERE dc.restaurant_id = r.id
      AND dc.title = 'Combo do Dia'
      AND dc.discount_percentage = 20
  );
