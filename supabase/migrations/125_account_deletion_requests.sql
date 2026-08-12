create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  email text,
  role text,
  status text not null default 'pending',
  reason text,
  source text not null default 'mobile_app',
  metadata jsonb not null default '{}'::jsonb,
  requested_at timestamptz not null default timezone('utc', now()),
  processed_at timestamptz,
  processed_by uuid references auth.users(id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint account_deletion_requests_status_check
    check (status in ('pending', 'approved', 'rejected', 'completed'))
);
create index if not exists idx_account_deletion_requests_user_id
  on public.account_deletion_requests(user_id);
create index if not exists idx_account_deletion_requests_status
  on public.account_deletion_requests(status, requested_at desc);
alter table public.account_deletion_requests enable row level security;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'account_deletion_requests'
      and policyname = 'Users can view own deletion requests'
  ) then
    create policy "Users can view own deletion requests"
      on public.account_deletion_requests
      for select
      using (auth.uid() = user_id);
  end if;
end
$$;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'account_deletion_requests'
      and policyname = 'Admins can view deletion requests'
  ) then
    create policy "Admins can view deletion requests"
      on public.account_deletion_requests
      for select
      using (
        exists (
          select 1
          from public.profiles p
          where p.id = auth.uid()
            and p.role = 'admin'
        )
      );
  end if;
end
$$;
create or replace function public.touch_account_deletion_requests_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;
drop trigger if exists trg_account_deletion_requests_updated_at
  on public.account_deletion_requests;
create trigger trg_account_deletion_requests_updated_at
before update on public.account_deletion_requests
for each row
execute function public.touch_account_deletion_requests_updated_at();
