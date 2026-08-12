begin;
create table if not exists core.integration_providers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  category text not null
    check (category in (
      'maps', 'push', 'sms', 'mobile_money', 'edge_security',
      'object_storage', 'media', 'ai', 'content_api'
    )),
  provider_name text not null,
  environment text not null default 'staging'
    check (environment in ('local', 'staging', 'production')),
  status text not null default 'planned'
    check (status in ('planned', 'configured', 'degraded', 'disabled')),
  secret_reference text,
  public_config jsonb not null default '{}'::jsonb,
  capabilities text[] not null default '{}',
  last_verified_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not (public_config ? 'secret')),
  check (not (public_config ? 'token')),
  check (not (public_config ? 'api_key')),
  check (not (public_config ? 'access_key'))
);
comment on table core.integration_providers is
  'Central provider catalogue. Contains no credentials; secret_reference names a Vault or Edge Function secret.';
create table if not exists core.app_integrations (
  id uuid primary key default gen_random_uuid(),
  app_id uuid not null references core.apps(id) on delete cascade,
  integration_provider_id uuid not null
    references core.integration_providers(id) on delete cascade,
  enabled boolean not null default false,
  priority smallint not null default 100 check (priority between 1 and 1000),
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (app_id, integration_provider_id)
);
create table if not exists core.integration_health_events (
  id bigint generated always as identity primary key,
  integration_provider_id uuid not null
    references core.integration_providers(id) on delete cascade,
  app_id uuid references core.apps(id) on delete set null,
  status text not null
    check (status in ('healthy', 'degraded', 'unavailable', 'misconfigured')),
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  error_code text,
  details jsonb not null default '{}'::jsonb,
  checked_at timestamptz not null default now()
);
create index if not exists idx_core_app_integrations_resolution
  on core.app_integrations (app_id, enabled, priority);
create index if not exists idx_core_integration_health_recent
  on core.integration_health_events (integration_provider_id, checked_at desc);
insert into core.integration_providers (
  code, category, provider_name, environment, status,
  secret_reference, capabilities, public_config
)
values
  (
    'maps_mapbox', 'maps', 'Mapbox', 'staging', 'planned',
    'MAPBOX_ACCESS_TOKEN',
    array['directions', 'geocoding', 'reverse_geocoding', 'map_matching'],
    '{"role":"primary","geocoding_storage":"temporary_by_default"}'
  ),
  (
    'maps_google', 'maps', 'Google Maps Platform', 'staging', 'planned',
    'GOOGLE_MAPS_API_KEY',
    array['routes', 'route_matrix', 'geocoding', 'reverse_geocoding'],
    '{"role":"fallback"}'
  ),
  (
    'push_firebase', 'push', 'Firebase Cloud Messaging', 'staging', 'planned',
    'FIREBASE_SERVICE_ACCOUNT_BY_APP',
    array['push_android', 'push_ios', 'push_web'],
    '{"credential_scope":"per_app"}'
  ),
  (
    'sms_mozesms', 'sms', 'MozeSMS', 'staging', 'configured',
    'MOZESMS_API_TOKEN',
    array['otp', 'transactional_sms'],
    '{}'
  ),
  (
    'money_vodacom_mpesa', 'mobile_money', 'Vodacom M-Pesa', 'staging', 'planned',
    'MPESA_OFFICIAL_CREDENTIALS',
    array['c2b', 'b2c', 'reversal', 'query_status'],
    '{"official_contract_required":true}'
  ),
  (
    'money_movitel_emola', 'mobile_money', 'Movitel e-Mola', 'staging', 'planned',
    'EMOLA_OFFICIAL_CREDENTIALS',
    array['collection', 'disbursement', 'reversal', 'query_status'],
    '{"official_contract_required":true}'
  ),
  (
    'edge_cloudflare', 'edge_security', 'Cloudflare', 'staging', 'planned',
    'CLOUDFLARE_API_TOKEN',
    array['dns', 'cdn', 'ddos', 'waf', 'rate_limiting'],
    '{}'
  ),
  (
    'storage_supabase', 'object_storage', 'Supabase Storage', 'staging', 'configured',
    null,
    array['private_documents', 'signed_urls', 'rls'],
    '{"role":"system_of_record"}'
  ),
  (
    'storage_cloudflare_r2', 'object_storage', 'Cloudflare R2', 'staging', 'planned',
    'CLOUDFLARE_R2_CREDENTIALS',
    array['s3_compatible', 'archive', 'public_assets'],
    '{"region":"auto","role":"archive_and_delivery"}'
  ),
  (
    'media_cloudinary', 'media', 'Cloudinary', 'staging', 'planned',
    'CLOUDINARY_URL',
    array['image_upload', 'image_transform', 'webp', 'avif', 'cdn'],
    '{"role":"public_media_derivatives"}'
  ),
  (
    'ai_gemini', 'ai', 'Google Gemini', 'staging', 'configured',
    'GEMINI_API_KEY',
    array['assistant', 'content_generation'],
    '{}'
  ),
  (
    'content_api_bible', 'content_api', 'API.Bible', 'staging', 'configured',
    'API_BIBLE_KEY',
    array['books', 'chapters', 'passages', 'search'],
    '{}'
  )
on conflict (code) do update
set category = excluded.category,
    provider_name = excluded.provider_name,
    secret_reference = excluded.secret_reference,
    capabilities = excluded.capabilities,
    public_config = excluded.public_config,
    updated_at = now();
insert into core.app_integrations (
  app_id, integration_provider_id, enabled, priority
)
select
  app.id,
  provider.id,
  case
    when provider.code in (
      'sms_mozesms', 'storage_supabase', 'ai_gemini'
    ) then true
    when provider.code = 'content_api_bible' and app.slug = 'comunhao' then true
    else false
  end,
  case
    when provider.code = 'maps_mapbox' then 10
    when provider.code = 'maps_google' then 20
    else 100
  end
from core.apps app
cross join core.integration_providers provider
where app.slug in ('deligo', 'sarca', 'taomoz', 'comunhao')
on conflict (app_id, integration_provider_id) do nothing;
alter table core.integration_providers enable row level security;
alter table core.app_integrations enable row level security;
alter table core.integration_health_events enable row level security;
drop policy if exists core_integration_providers_admin_read
  on core.integration_providers;
create policy core_integration_providers_admin_read
on core.integration_providers
for select
to authenticated
using (core.is_platform_admin(auth.uid()));
drop policy if exists core_app_integrations_admin_read
  on core.app_integrations;
create policy core_app_integrations_admin_read
on core.app_integrations
for select
to authenticated
using (core.is_platform_admin(auth.uid()));
drop policy if exists core_integration_health_admin_read
  on core.integration_health_events;
create policy core_integration_health_admin_read
on core.integration_health_events
for select
to authenticated
using (core.is_platform_admin(auth.uid()));
grant select on core.integration_providers to authenticated;
grant select on core.app_integrations to authenticated;
grant select on core.integration_health_events to authenticated;
grant all on core.integration_providers to service_role;
grant all on core.app_integrations to service_role;
grant all on core.integration_health_events to service_role;
grant usage, select on sequence core.integration_health_events_id_seq
  to service_role;
commit;
