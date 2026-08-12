create table if not exists public.maps_gateway_cache (
  cache_key text primary key,
  action text not null check (action in ('route', 'search', 'reverse')),
  payload jsonb not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.maps_gateway_cache enable row level security;
revoke all on table public.maps_gateway_cache from anon, authenticated;
create index if not exists maps_gateway_cache_expiry_idx
  on public.maps_gateway_cache (expires_at);
create or replace function public.cleanup_maps_gateway_cache()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer;
begin
  delete from public.maps_gateway_cache where expires_at < now();
  get diagnostics removed = row_count;
  return removed;
end;
$$;
revoke all on function public.cleanup_maps_gateway_cache() from public;
