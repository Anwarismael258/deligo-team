-- Add neighborhood/city to user_addresses for filtering

ALTER TABLE public.user_addresses
  ADD COLUMN IF NOT EXISTS neighborhood TEXT,
  ADD COLUMN IF NOT EXISTS city TEXT;
