begin;

do $$
declare constraint_name text;
begin
  select c.conname into constraint_name
  from pg_constraint c
  join pg_class r on r.oid = c.conrelid
  join pg_namespace n on n.oid = r.relnamespace
  where n.nspname = 'hq' and r.relname = 'marketing_campaigns' and c.contype = 'c'
    and pg_get_constraintdef(c.oid) ilike '%status%'
  limit 1;
  if constraint_name is not null then
    execute format('alter table hq.marketing_campaigns drop constraint %I', constraint_name);
  end if;
end $$;

update hq.marketing_campaigns set status = 'pending_approval' where status = 'review';

alter table hq.marketing_campaigns
  add column if not exists objective text,
  add column if not exists target_audience jsonb not null default '{}'::jsonb,
  add column if not exists budget_amount numeric(18,2) not null default 0 check (budget_amount >= 0),
  add column if not exists currency text not null default 'MZN',
  add column if not exists approval_request_id uuid references hq.approval_requests(id),
  add column if not exists published_at timestamptz,
  add column if not exists paused_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists archived_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

alter table hq.marketing_campaigns add constraint marketing_campaigns_status_check
  check (status in ('draft','pending_approval','approved','published','paused','completed','archived','rejected'));

create table if not exists hq.marketing_channels (
  id uuid primary key default gen_random_uuid(), campaign_id uuid not null references hq.marketing_campaigns(id) on delete cascade,
  channel text not null check (channel in ('social','email','push','sms','web','in_app','field','partner')),
  account_reference text, status text not null default 'planned' check (status in ('planned','active','paused','completed')),
  created_at timestamptz not null default now()
);
create table if not exists hq.marketing_content_calendar (
  id uuid primary key default gen_random_uuid(), campaign_id uuid not null references hq.marketing_campaigns(id) on delete cascade,
  platform_id uuid references hq.platforms(id), channel_id uuid references hq.marketing_channels(id) on delete set null,
  title text not null, content_type text not null, scheduled_at timestamptz not null, published_at timestamptz,
  status text not null default 'draft' check (status in ('draft','scheduled','published','cancelled')),
  created_by uuid references hq.employees(id), created_at timestamptz not null default now()
);
create table if not exists hq.marketing_promotions (
  id uuid primary key default gen_random_uuid(), campaign_id uuid not null references hq.marketing_campaigns(id) on delete cascade,
  platform_id uuid references hq.platforms(id), code text not null,
  discount_type text not null check (discount_type in ('percentage','fixed','free_delivery')),
  discount_value numeric(18,2) not null default 0 check (discount_value >= 0), starts_at timestamptz, ends_at timestamptz,
  status text not null default 'draft' check (status in ('draft','active','paused','expired','archived')),
  usage_limit integer check (usage_limit is null or usage_limit > 0), usage_count integer not null default 0 check (usage_count >= 0),
  created_at timestamptz not null default now(), unique (campaign_id, code)
);
create table if not exists hq.marketing_creatives (
  id uuid primary key default gen_random_uuid(), campaign_id uuid not null references hq.marketing_campaigns(id) on delete cascade,
  title text not null, creative_type text not null, storage_reference text not null, version integer not null default 1 check (version > 0),
  status text not null default 'draft' check (status in ('draft','review','approved','archived')),
  created_by uuid references hq.employees(id), created_at timestamptz not null default now()
);
create table if not exists hq.marketing_leads (
  id uuid primary key default gen_random_uuid(), campaign_id uuid not null references hq.marketing_campaigns(id) on delete cascade,
  platform_id uuid references hq.platforms(id), external_reference text, source_channel text,
  status text not null default 'new' check (status in ('new','qualified','converted','lost')),
  converted_at timestamptz, created_at timestamptz not null default now()
);
create unique index if not exists uq_marketing_lead_reference on hq.marketing_leads(campaign_id, external_reference) where external_reference is not null;
create table if not exists hq.marketing_metrics (
  id uuid primary key default gen_random_uuid(), campaign_id uuid not null references hq.marketing_campaigns(id) on delete cascade,
  platform_id uuid references hq.platforms(id), metric_date date not null,
  impressions integer not null default 0 check (impressions >= 0), clicks integer not null default 0 check (clicks >= 0),
  leads integer not null default 0 check (leads >= 0), conversions integer not null default 0 check (conversions >= 0),
  spend numeric(18,2) not null default 0 check (spend >= 0), created_at timestamptz not null default now()
);
create unique index if not exists uq_marketing_metrics_context on hq.marketing_metrics(campaign_id, coalesce(platform_id,'00000000-0000-0000-0000-000000000000'::uuid), metric_date);
create table if not exists hq.marketing_history (
  id uuid primary key default gen_random_uuid(), campaign_id uuid not null references hq.marketing_campaigns(id) on delete cascade,
  event_type text not null, description text not null, actor_employee_id uuid references hq.employees(id),
  metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

create or replace function hq.enforce_marketing_campaign_transition() returns trigger language plpgsql security definer set search_path = hq, public as $$
declare approval_status text;
begin
  if new.status = old.status then new.updated_at := now(); return new; end if;
  if new.status = 'pending_approval' and old.status <> 'draft' then raise exception 'Apenas campanhas em rascunho podem ser submetidas'; end if;
  if new.status = 'approved' then
    select status into approval_status from hq.approval_requests where id = new.approval_request_id;
    if approval_status is distinct from 'approved' then raise exception 'A campanha ainda nao foi aprovada'; end if;
  end if;
  if new.status = 'published' then
    select status into approval_status from hq.approval_requests where id = new.approval_request_id;
    if old.status not in ('approved','paused') or approval_status is distinct from 'approved' then raise exception 'Publicacao exige aprovacao valida'; end if;
    new.published_at := coalesce(new.published_at, now());
  elsif new.status = 'paused' then
    if old.status <> 'published' then raise exception 'Apenas campanhas publicadas podem ser pausadas'; end if;
    new.paused_at := now();
  elsif new.status = 'completed' then
    if old.status not in ('published','paused') then raise exception 'Campanha nao esta em execucao'; end if;
    new.completed_at := now();
  elsif new.status = 'archived' then new.archived_at := now();
  end if;
  new.updated_at := now(); return new;
end $$;
drop trigger if exists trg_marketing_campaign_transition on hq.marketing_campaigns;
create trigger trg_marketing_campaign_transition before update on hq.marketing_campaigns for each row execute function hq.enforce_marketing_campaign_transition();

create index if not exists idx_marketing_campaign_status on hq.marketing_campaigns(status, created_at desc);
create index if not exists idx_marketing_calendar_schedule on hq.marketing_content_calendar(scheduled_at, status);
create index if not exists idx_marketing_history_campaign on hq.marketing_history(campaign_id, created_at desc);

do $$ declare t text; begin
  foreach t in array array['marketing_channels','marketing_content_calendar','marketing_promotions','marketing_creatives','marketing_leads','marketing_metrics','marketing_history']
  loop
    execute format('alter table hq.%I enable row level security', t);
    execute format('revoke all on hq.%I from public, anon, authenticated', t);
    execute format('grant all on hq.%I to service_role', t);
  end loop;
end $$;
revoke all on function hq.enforce_marketing_campaign_transition() from public, anon, authenticated;
grant execute on function hq.enforce_marketing_campaign_transition() to service_role;

commit;
