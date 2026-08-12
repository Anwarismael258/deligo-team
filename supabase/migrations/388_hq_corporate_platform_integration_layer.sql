begin;

-- The HQ registry remains the single source of corporate platform identity.
-- Existing slugs are retained so legacy applications are not broken.
create schema if not exists exploremoz;
grant usage on schema exploremoz to service_role;

do $$ declare constraint_name text; begin
  select conname into constraint_name from pg_constraint
  where conrelid = 'core.apps'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%module_schema%' limit 1;
  if constraint_name is not null then execute format('alter table core.apps drop constraint %I', constraint_name); end if;
end $$;
alter table core.apps add constraint core_apps_module_schema_check
  check (module_schema in ('deligo','comunhao','sarca','taomoz','mestre24','exploremoz'));

alter table hq.platforms
  add column if not exists platform_code text,
  add column if not exists base_url text,
  add column if not exists icon_key text,
  add column if not exists integration_status text not null default 'connected'
    check (integration_status in ('connected','partial','planned','disabled'));

update hq.platforms set platform_code = case slug
  when 'deligo' then 'DELIGO'
  when 'sarca' then 'SARCA'
  when 'taomoz' then 'DELIGO_MARKETING'
  when 'comunhao' then 'COMUNHAO'
  when 'mestre24' then 'MESTRE24'
  when 'exploremoz' then 'EXPLOREMOZ'
  else platform_code
end where platform_code is null;

create unique index if not exists hq_platforms_platform_code_key
  on hq.platforms(platform_code) where platform_code is not null;

insert into hq.platforms(
  id, legal_entity_id, slug, name, schema_name, status, platform_code, icon_key, integration_status
) values (
  '20000000-0000-0000-0000-000000000006',
  '10000000-0000-0000-0000-000000000001',
  'exploremoz', 'ExploreMoz', 'exploremoz', 'inactive', 'EXPLOREMOZ', 'travel_explore', 'planned'
)
on conflict(slug) do update set
  name = excluded.name, schema_name = excluded.schema_name,
  platform_code = excluded.platform_code, icon_key = excluded.icon_key,
  integration_status = excluded.integration_status;

update hq.platforms
set name = 'DeliGo Market', platform_code = 'DELIGO_MARKETING', icon_key = 'storefront'
where slug = 'taomoz';

-- Append-only operational event stream. It never replaces a platform's own
-- operational tables; it is the safe corporate integration and observability layer.
create table if not exists hq.platform_events (
  id uuid primary key default gen_random_uuid(),
  platform_id uuid not null references hq.platforms(id),
  source_app text not null,
  source_event_id text,
  event_type text not null,
  entity_type text not null,
  entity_id text not null,
  user_id uuid references auth.users(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (jsonb_typeof(payload) = 'object')
);
create unique index if not exists hq_platform_events_source_unique
  on hq.platform_events(platform_id, source_app, source_event_id)
  where source_event_id is not null;
create index if not exists hq_platform_events_feed_idx
  on hq.platform_events(platform_id, occurred_at desc);
create index if not exists hq_platform_events_entity_idx
  on hq.platform_events(entity_type, entity_id, occurred_at desc);
create index if not exists hq_platform_events_user_idx
  on hq.platform_events(user_id, occurred_at desc) where user_id is not null;

-- Financial integration records are a consolidated read model. Operational
-- ledgers and payment-provider records remain in their owning domains.
create table if not exists hq.platform_financial_events (
  id uuid primary key default gen_random_uuid(),
  platform_id uuid not null references hq.platforms(id),
  source_app text not null,
  source_record_id text,
  transaction_type text not null,
  entity_type text,
  entity_id text,
  user_id uuid references auth.users(id) on delete set null,
  gross_amount numeric(18,2) not null check (gross_amount >= 0),
  platform_fee numeric(18,2) not null default 0 check (platform_fee >= 0),
  provider_fee numeric(18,2) not null default 0 check (provider_fee >= 0),
  partner_amount numeric(18,2) not null default 0 check (partner_amount >= 0),
  currency text not null default 'MZN',
  payment_method text,
  payment_status text not null default 'pending'
    check (payment_status in ('pending','authorized','confirmed','failed','refunded','reversed','cancelled')),
  reference text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (jsonb_typeof(metadata) = 'object')
);
create unique index if not exists hq_platform_financial_events_source_unique
  on hq.platform_financial_events(platform_id, source_app, source_record_id)
  where source_record_id is not null;
create index if not exists hq_platform_financial_events_feed_idx
  on hq.platform_financial_events(platform_id, occurred_at desc, payment_status);

create table if not exists hq.central_daily_metrics (
  metric_date date not null,
  platform_id uuid not null references hq.platforms(id),
  metric_code text not null,
  metric_value numeric(20,4) not null default 0,
  dimensions jsonb not null default '{}'::jsonb,
  calculated_at timestamptz not null default now(),
  primary key(metric_date, platform_id, metric_code),
  check (jsonb_typeof(dimensions) = 'object')
);
create index if not exists hq_central_daily_metrics_platform_idx
  on hq.central_daily_metrics(platform_id, metric_date desc);

create table if not exists hq.platform_notification_requests (
  id uuid primary key default gen_random_uuid(),
  platform_id uuid not null references hq.platforms(id),
  target_type text not null check (target_type in ('user','role','city','segment','platform')),
  target_reference text,
  title text not null,
  body text not null,
  channels text[] not null default array['in_app']::text[],
  status text not null default 'draft' check (status in ('draft','approved','queued','sent','cancelled','failed')),
  requested_by uuid references hq.employees(id),
  approved_by uuid references hq.employees(id),
  scheduled_for timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists hq_platform_notification_requests_status_idx
  on hq.platform_notification_requests(platform_id, status, scheduled_for);

alter table hq.platform_events enable row level security;
alter table hq.platform_financial_events enable row level security;
alter table hq.central_daily_metrics enable row level security;
alter table hq.platform_notification_requests enable row level security;
grant select, insert, update, delete on hq.platform_events, hq.platform_financial_events,
  hq.central_daily_metrics, hq.platform_notification_requests to service_role;

create or replace function public.hq_ingest_platform_event_v1(
  p_platform_slug text, p_source_app text, p_event_type text, p_entity_type text,
  p_entity_id text, p_source_event_id text default null, p_user_id uuid default null,
  p_actor_user_id uuid default null, p_payload jsonb default '{}'::jsonb,
  p_occurred_at timestamptz default now()
) returns uuid
language plpgsql security definer set search_path = hq, public, pg_temp as $$
declare v_platform hq.platforms; v_event_id uuid;
begin
  if coalesce(nullif(trim(p_source_app), ''), '') = '' or coalesce(nullif(trim(p_event_type), ''), '') = ''
    or coalesce(nullif(trim(p_entity_type), ''), '') = '' or coalesce(nullif(trim(p_entity_id), ''), '') = '' then
    raise exception 'HQ_EVENT_REQUIRED_FIELDS_MISSING';
  end if;
  if jsonb_typeof(coalesce(p_payload, '{}'::jsonb)) <> 'object' then raise exception 'HQ_EVENT_PAYLOAD_MUST_BE_OBJECT'; end if;
  select * into v_platform from hq.platforms where slug = lower(trim(p_platform_slug));
  if not found or v_platform.integration_status in ('disabled','planned') then raise exception 'HQ_PLATFORM_NOT_AVAILABLE_FOR_EVENTS'; end if;
  insert into hq.platform_events(platform_id, source_app, source_event_id, event_type, entity_type, entity_id, user_id, actor_user_id, payload, occurred_at)
  values(v_platform.id, trim(p_source_app), nullif(trim(p_source_event_id), ''), trim(p_event_type), trim(p_entity_type), trim(p_entity_id), p_user_id, p_actor_user_id, coalesce(p_payload, '{}'::jsonb), coalesce(p_occurred_at, now()))
  on conflict(platform_id, source_app, source_event_id) where source_event_id is not null
  do update set payload = excluded.payload, occurred_at = excluded.occurred_at
  returning id into v_event_id;
  return v_event_id;
end;
$$;

create or replace function public.hq_ingest_platform_financial_event_v1(
  p_platform_slug text, p_source_app text, p_transaction_type text, p_gross_amount numeric,
  p_payment_status text, p_source_record_id text default null, p_entity_type text default null,
  p_entity_id text default null, p_user_id uuid default null, p_platform_fee numeric default 0,
  p_provider_fee numeric default 0, p_partner_amount numeric default 0, p_currency text default 'MZN',
  p_payment_method text default null, p_reference text default null, p_metadata jsonb default '{}'::jsonb,
  p_occurred_at timestamptz default now()
) returns uuid
language plpgsql security definer set search_path = hq, public, pg_temp as $$
declare v_platform hq.platforms; v_event_id uuid;
begin
  if coalesce(nullif(trim(p_source_app), ''), '') = '' or coalesce(nullif(trim(p_transaction_type), ''), '') = '' or p_gross_amount is null or p_gross_amount < 0 then
    raise exception 'HQ_FINANCIAL_REQUIRED_FIELDS_MISSING';
  end if;
  if p_payment_status not in ('pending','authorized','confirmed','failed','refunded','reversed','cancelled') then raise exception 'HQ_FINANCIAL_INVALID_PAYMENT_STATUS'; end if;
  if jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object' then raise exception 'HQ_FINANCIAL_METADATA_MUST_BE_OBJECT'; end if;
  select * into v_platform from hq.platforms where slug = lower(trim(p_platform_slug));
  if not found or v_platform.integration_status in ('disabled','planned') then raise exception 'HQ_PLATFORM_NOT_AVAILABLE_FOR_FINANCE'; end if;
  insert into hq.platform_financial_events(platform_id, source_app, source_record_id, transaction_type, entity_type, entity_id, user_id, gross_amount, platform_fee, provider_fee, partner_amount, currency, payment_method, payment_status, reference, metadata, occurred_at)
  values(v_platform.id, trim(p_source_app), nullif(trim(p_source_record_id), ''), trim(p_transaction_type), nullif(trim(p_entity_type), ''), nullif(trim(p_entity_id), ''), p_user_id, p_gross_amount, greatest(coalesce(p_platform_fee, 0), 0), greatest(coalesce(p_provider_fee, 0), 0), greatest(coalesce(p_partner_amount, 0), 0), upper(coalesce(nullif(trim(p_currency), ''), 'MZN')), nullif(trim(p_payment_method), ''), p_payment_status, nullif(trim(p_reference), ''), coalesce(p_metadata, '{}'::jsonb), coalesce(p_occurred_at, now()))
  on conflict(platform_id, source_app, source_record_id) where source_record_id is not null
  do update set payment_status = excluded.payment_status, gross_amount = excluded.gross_amount, platform_fee = excluded.platform_fee, provider_fee = excluded.provider_fee, partner_amount = excluded.partner_amount, reference = excluded.reference, metadata = excluded.metadata, occurred_at = excluded.occurred_at
  returning id into v_event_id;
  return v_event_id;
end;
$$;

create or replace view hq.global_user_platforms_v1 as
select
  p.user_id, p.full_name, p.display_name, p.primary_phone, p.primary_email, p.profile_status,
  a.slug as app_slug, a.display_name as app_name, m.membership_status, m.joined_at, m.last_seen_at,
  coalesce(jsonb_agg(distinct r.slug) filter (where r.slug is not null), '[]'::jsonb) as roles
from core.profiles p
left join core.user_app_memberships m on m.user_id = p.user_id
left join core.apps a on a.id = m.app_id
left join core.user_roles ur on ur.user_id = p.user_id and ur.starts_at <= now() and (ur.ends_at is null or ur.ends_at > now())
left join core.roles r on r.id = ur.role_id and (r.app_id is null or r.app_id = a.id)
group by p.user_id, p.full_name, p.display_name, p.primary_phone, p.primary_email, p.profile_status, a.slug, a.display_name, m.membership_status, m.joined_at, m.last_seen_at;

revoke all on function public.hq_ingest_platform_event_v1(text,text,text,text,text,text,uuid,uuid,jsonb,timestamptz) from public, anon, authenticated;
revoke all on function public.hq_ingest_platform_financial_event_v1(text,text,text,numeric,text,text,text,text,uuid,numeric,numeric,numeric,text,text,text,jsonb,timestamptz) from public, anon, authenticated;
grant execute on function public.hq_ingest_platform_event_v1(text,text,text,text,text,text,uuid,uuid,jsonb,timestamptz) to service_role;
grant execute on function public.hq_ingest_platform_financial_event_v1(text,text,text,numeric,text,text,text,text,uuid,numeric,numeric,numeric,text,text,text,jsonb,timestamptz) to service_role;
grant select on hq.global_user_platforms_v1 to service_role;

insert into core.apps(slug, name, display_name, description, runtime_type, module_schema, is_active, is_public)
values ('exploremoz', 'ExploreMoz', 'ExploreMoz', 'Exploração, parceiros e experiências em Moçambique.', 'mobile', 'exploremoz', false, true)
on conflict(slug) do update set name = excluded.name, display_name = excluded.display_name, description = excluded.description, module_schema = excluded.module_schema;

notify pgrst, 'reload schema';
commit;
