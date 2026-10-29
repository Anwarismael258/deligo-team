-- Read-only aliases for the already-deployed institutional news and careers readers.
-- Canonical fields, publication state, existing content and RLS remain authoritative.
alter table public.news add column if not exists date timestamptz generated always as (coalesce(published_at,created_at)) stored;
alter table public.news add column if not exists body text[] generated always as (string_to_array(coalesce(content,''),E'\n\n')) stored;
alter table public.news add column if not exists author text generated always as (coalesce(author_name,'DeliGo Triunfal, Lda.')) stored;
alter table public.news add column if not exists image_url text generated always as (cover_image_url) stored;
alter table public.job_openings add column if not exists area text generated always as (department) stored;
alter table public.job_openings add column if not exists type text generated always as (employment_type) stored;
notify pgrst,'reload schema';
