begin;
create table if not exists core.mobile_app_clients (
  id uuid primary key default gen_random_uuid(),
  app_id uuid not null references core.apps(id) on delete cascade,
  client_slug text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web')),
  package_name text not null unique,
  firebase_project_id text not null,
  firebase_app_id text,
  status text not null default 'active'
    check (status in ('planned', 'active', 'deprecated', 'disabled')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (app_id, client_slug)
);
comment on table core.mobile_app_clients is
  'Known mobile/web clients and Firebase project mapping. Client API keys and service-account material are never stored here.';
alter table core.user_devices
  add column if not exists mobile_app_client_id uuid
    references core.mobile_app_clients(id) on delete set null;
create index if not exists idx_core_mobile_clients_app
  on core.mobile_app_clients (app_id, status);
create index if not exists idx_core_user_devices_client
  on core.user_devices (mobile_app_client_id, is_active);
insert into core.mobile_app_clients (
  app_id, client_slug, platform, package_name, firebase_project_id,
  firebase_app_id, status, metadata
)
select app.id, seed.client_slug, 'android', seed.package_name,
  seed.firebase_project_id, seed.firebase_app_id, 'active',
  jsonb_build_object('source', 'existing_google_services')
from (
  values
    ('deligo', 'deligo_customer', 'com.deligo.app', 'deligo-247', '1:704684828842:android:8c861a9461ce27067588d3'),
    ('deligo', 'deligo_admin', 'com.example.deligo247', 'deligo-247', '1:704684828842:android:d5f3e158dc3c0f2b7588d3'),
    ('deligo', 'deligo_field', 'deligo.field', 'deligo-247', '1:704684828842:android:084af5285004b5ac7588d3'),
    ('deligo', 'deligo_marketing', 'deligo.marketing', 'deligo-247', '1:704684828842:android:1462193608fd80dc7588d3'),
    ('comunhao', 'comunhao_members', 'moz.comunhao.membros', 'comunhao-97246', '1:266409982212:android:39c61553e6b4b1ab1f7851'),
    ('comunhao', 'comunhao_churches', 'moz.comuhao.igrejas', 'comunhao-97246', '1:266409982212:android:205ac3da370535691f7851'),
    ('comunhao', 'comunhao_super_admin', 'moz.comunhao.admin', 'comunhao-97246', '1:266409982212:android:9ee281630a36b0fd1f7851'),
    ('sarca', 'sarca_driver', 'com.sarca.driver', 'sarca-mobilidadepagamentos', '1:1021495835528:android:8afb3493f60180f5cd183d'),
    ('sarca', 'sarca_rider', 'com.sarca.rider', 'sarca-mobilidadepagamentos', '1:1021495835528:android:b055143411365f86cd183d')
) as seed(app_slug, client_slug, package_name, firebase_project_id, firebase_app_id)
join core.apps app on app.slug = seed.app_slug
on conflict (client_slug) do update
set package_name = excluded.package_name,
    firebase_project_id = excluded.firebase_project_id,
    firebase_app_id = excluded.firebase_app_id,
    status = excluded.status,
    metadata = excluded.metadata,
    updated_at = now();
create or replace function core.register_mobile_push_device(
  p_client_slug text,
  p_push_token text,
  p_device_label text default null,
  p_app_version text default null,
  p_os_version text default null
)
returns core.user_devices
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_client core.mobile_app_clients%rowtype;
  v_device core.user_devices%rowtype;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '28000';
  end if;
  if length(trim(coalesce(p_push_token, ''))) < 20 then
    raise exception 'invalid_push_token' using errcode = '22023';
  end if;

  select * into v_client
  from core.mobile_app_clients c
  where c.client_slug = lower(trim(p_client_slug))
    and c.status = 'active';
  if not found then
    raise exception 'mobile_client_not_active' using errcode = '42501';
  end if;

  if not exists (
    select 1 from core.user_app_memberships m
    where m.user_id = v_user_id
      and m.app_id = v_client.app_id
      and m.membership_status = 'active'
  ) then
    raise exception 'app_membership_required' using errcode = '42501';
  end if;

  insert into core.user_devices (
    user_id, app_id, mobile_app_client_id, device_type, push_provider,
    push_token, device_label, app_version, os_version, last_seen_at, is_active
  ) values (
    v_user_id, v_client.app_id, v_client.id, 'android', 'fcm',
    trim(p_push_token), nullif(trim(p_device_label), ''),
    nullif(trim(p_app_version), ''), nullif(trim(p_os_version), ''), now(), true
  )
  on conflict (app_id, push_provider, push_token) where push_token is not null
  do update set
    user_id = excluded.user_id,
    mobile_app_client_id = excluded.mobile_app_client_id,
    device_label = coalesce(excluded.device_label, core.user_devices.device_label),
    app_version = coalesce(excluded.app_version, core.user_devices.app_version),
    os_version = coalesce(excluded.os_version, core.user_devices.os_version),
    last_seen_at = now(),
    is_active = true,
    updated_at = now()
  returning * into v_device;

  return v_device;
end;
$$;
revoke all on function core.register_mobile_push_device(text, text, text, text, text)
  from public;
grant execute on function core.register_mobile_push_device(text, text, text, text, text)
  to authenticated;
alter table core.mobile_app_clients enable row level security;
drop policy if exists core_mobile_clients_read_self_app on core.mobile_app_clients;
create policy core_mobile_clients_read_self_app
on core.mobile_app_clients
for select
to authenticated
using (
  core.is_platform_admin(auth.uid())
  or exists (
    select 1 from core.user_app_memberships m
    where m.user_id = auth.uid()
      and m.app_id = mobile_app_clients.app_id
      and m.membership_status = 'active'
  )
);
grant select on core.mobile_app_clients to authenticated;
grant all on core.mobile_app_clients to service_role;
commit;
