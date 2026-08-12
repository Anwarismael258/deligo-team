-- Add neighborhood/city fields to restaurants for location filters

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS neighborhood TEXT,
  ADD COLUMN IF NOT EXISTS city TEXT;
