begin;

create table if not exists public.job_applications(
  id uuid primary key default gen_random_uuid(),
  job_opening_id uuid not null references public.job_openings(id),
  full_name text not null,
  email text not null,
  phone text,
  cv_url text,
  cover_note text,
  status text not null default 'received' check (status in ('received','screening','interview','approved','rejected','hired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_job_applications_job_status on public.job_applications(job_opening_id,status,created_at desc);
alter table public.job_applications enable row level security;
revoke all on public.job_applications from anon,authenticated;
grant insert on public.job_applications to anon;
drop policy if exists job_applications_public_insert on public.job_applications;
create policy job_applications_public_insert on public.job_applications for insert to anon
  with check (exists (select 1 from public.job_openings j where j.id=job_opening_id and j.published=true));

commit;
