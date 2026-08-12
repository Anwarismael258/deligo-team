-- Multi-device FCM token registry
create table if not exists public.user_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  device_id text,
  platform text,
  app_version text,
  is_active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_user_push_tokens_user_active_seen
  on public.user_push_tokens(user_id, is_active, last_seen_at desc);
create index if not exists idx_user_push_tokens_token
  on public.user_push_tokens(token);
do $$
begin
  if exists (
    select 1
    from pg_proc
    where proname = 'touch_updated_at'
      and pg_function_is_visible(oid)
  ) then
    drop trigger if exists trg_user_push_tokens_touch_updated_at on public.user_push_tokens;
    create trigger trg_user_push_tokens_touch_updated_at
    before update on public.user_push_tokens
    for each row execute function public.touch_updated_at();
  end if;
end
$$;
alter table public.user_push_tokens enable row level security;
drop policy if exists user_push_tokens_select_own on public.user_push_tokens;
create policy user_push_tokens_select_own
  on public.user_push_tokens
  for select
  to authenticated
  using (auth.uid() = user_id or public.is_admin());
drop policy if exists user_push_tokens_insert_own on public.user_push_tokens;
create policy user_push_tokens_insert_own
  on public.user_push_tokens
  for insert
  to authenticated
  with check (auth.uid() = user_id or public.is_admin());
drop policy if exists user_push_tokens_update_own on public.user_push_tokens;
create policy user_push_tokens_update_own
  on public.user_push_tokens
  for update
  to authenticated
  using (auth.uid() = user_id or public.is_admin())
  with check (auth.uid() = user_id or public.is_admin());
drop policy if exists user_push_tokens_delete_own on public.user_push_tokens;
create policy user_push_tokens_delete_own
  on public.user_push_tokens
  for delete
  to authenticated
  using (auth.uid() = user_id or public.is_admin());
drop policy if exists user_push_tokens_service_all on public.user_push_tokens;
create policy user_push_tokens_service_all
  on public.user_push_tokens
  for all
  to service_role
  using (true)
  with check (true);
