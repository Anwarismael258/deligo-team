-- Ensure profiles.phone has a default to avoid auth triggers failing on insert
ALTER TABLE public.profiles
  ALTER COLUMN phone SET DEFAULT '+258000000000';
