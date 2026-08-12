begin;
insert into core.roles (slug, name, scope, app_id, description)
values
  ('platform_support_agent', 'Platform Support Agent', 'platform', null,
   'Provides support for the platform apps explicitly assigned to the worker.'),
  ('platform_support_lead', 'Platform Support Lead', 'platform', null,
   'Supervises cross-platform support and escalations.'),
  ('platform_marketing_agent', 'Platform Marketing Agent', 'platform', null,
   'Creates campaigns for assigned platform apps.'),
  ('platform_marketing_manager', 'Platform Marketing Manager', 'platform', null,
   'Approves and manages cross-platform campaigns.'),
  ('platform_field_agent', 'Platform Field Agent', 'platform', null,
   'Performs field work for any assigned platform app.'),
  ('platform_field_supervisor', 'Platform Field Supervisor', 'platform', null,
   'Assigns and supervises cross-platform field operations.')
on conflict (slug) do update set
  name = excluded.name,
  scope = excluded.scope,
  app_id = null,
  description = excluded.description,
  updated_at = now();
with grants(role_slug, permission_code) as (
  values
    ('platform_support_agent', 'support.case.read'),
    ('platform_support_agent', 'support.case.manage'),
    ('platform_support_agent', 'support.user.read'),
    ('platform_support_lead', 'support.case.read'),
    ('platform_support_lead', 'support.case.manage'),
    ('platform_support_lead', 'support.user.read'),
    ('platform_support_lead', 'platform.dashboard.read'),
    ('platform_marketing_agent', 'marketing.campaign.read'),
    ('platform_marketing_manager', 'marketing.campaign.read'),
    ('platform_marketing_manager', 'marketing.campaign.manage'),
    ('platform_marketing_manager', 'marketing.audience.manage'),
    ('platform_field_agent', 'field.merchant.read'),
    ('platform_field_agent', 'field.merchant.onboard'),
    ('platform_field_agent', 'field.visit.manage'),
    ('platform_field_supervisor', 'field.merchant.read'),
    ('platform_field_supervisor', 'field.merchant.onboard'),
    ('platform_field_supervisor', 'field.visit.manage'),
    ('platform_field_supervisor', 'platform.dashboard.read')
)
insert into core.role_permissions(role_id, permission_id)
select r.id, p.id
from grants g
join core.roles r on r.slug = g.role_slug
join core.permissions p on p.code = g.permission_code
on conflict do nothing;
create table if not exists core.staff_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  employee_code text unique,
  department text not null
    check (department in ('support', 'marketing', 'field', 'operations', 'finance', 'technology', 'management')),
  job_title text,
  supervisor_user_id uuid references auth.users(id) on delete set null,
  employment_status text not null default 'active'
    check (employment_status in ('invited', 'active', 'suspended', 'terminated')),
  hired_at date,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists core.staff_app_scopes (
  staff_user_id uuid not null references core.staff_profiles(user_id) on delete cascade,
  app_id uuid not null references core.apps(id) on delete cascade,
  can_read boolean not null default true,
  can_manage boolean not null default false,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  assigned_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  primary key (staff_user_id, app_id)
);
create table if not exists core.support_cases (
  id uuid primary key default gen_random_uuid(),
  case_number bigint generated always as identity unique,
  app_id uuid not null references core.apps(id) on delete restrict,
  requester_user_id uuid references auth.users(id) on delete set null,
  requester_name text,
  requester_phone text,
  requester_email text,
  category text not null default 'general',
  subject text not null,
  description text not null,
  status text not null default 'open'
    check (status in ('open', 'assigned', 'waiting_customer', 'waiting_internal', 'resolved', 'closed', 'cancelled')),
  priority text not null default 'normal'
    check (priority in ('low', 'normal', 'high', 'urgent', 'critical')),
  assigned_team text,
  assigned_user_id uuid references auth.users(id) on delete set null,
  entity_schema text,
  entity_table text,
  entity_id text,
  source_channel text not null default 'app'
    check (source_channel in ('app', 'web', 'phone', 'email', 'sms', 'whatsapp', 'staff')),
  first_response_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,
  sla_due_at timestamptz,
  tags text[] not null default '{}',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists core.support_case_messages (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references core.support_cases(id) on delete cascade,
  author_user_id uuid references auth.users(id) on delete set null,
  author_type text not null
    check (author_type in ('customer', 'staff', 'system')),
  body text not null,
  is_internal boolean not null default false,
  attachments jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create table if not exists core.support_case_events (
  id bigint generated always as identity primary key,
  case_id uuid not null references core.support_cases(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  old_value jsonb,
  new_value jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create table if not exists core.marketing_campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  campaign_type text not null
    check (campaign_type in ('push', 'sms', 'email', 'in_app', 'promotion', 'multi_channel')),
  status text not null default 'draft'
    check (status in ('draft', 'pending_approval', 'approved', 'scheduled', 'running', 'paused', 'completed', 'cancelled')),
  created_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid references auth.users(id) on delete set null,
  scheduled_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  content jsonb not null default '{}'::jsonb,
  audience_rules jsonb not null default '{}'::jsonb,
  budget_minor bigint check (budget_minor is null or budget_minor >= 0),
  currency_code char(3) not null default 'MZN',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists core.marketing_campaign_apps (
  campaign_id uuid not null references core.marketing_campaigns(id) on delete cascade,
  app_id uuid not null references core.apps(id) on delete cascade,
  app_content jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  primary key (campaign_id, app_id)
);
create table if not exists core.marketing_deliveries (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references core.marketing_campaigns(id) on delete cascade,
  app_id uuid not null references core.apps(id) on delete cascade,
  recipient_user_id uuid references auth.users(id) on delete set null,
  channel text not null check (channel in ('push', 'sms', 'email', 'in_app')),
  destination_hash text,
  status text not null default 'queued'
    check (status in ('queued', 'sent', 'delivered', 'opened', 'clicked', 'failed', 'skipped', 'unsubscribed')),
  provider text,
  provider_reference text,
  error_code text,
  sent_at timestamptz,
  delivered_at timestamptz,
  opened_at timestamptz,
  clicked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create table if not exists core.field_workers (
  user_id uuid primary key references core.staff_profiles(user_id) on delete cascade,
  worker_type text not null default 'agent'
    check (worker_type in ('agent', 'supervisor', 'contractor')),
  home_province text,
  home_city text,
  can_travel boolean not null default false,
  is_available boolean not null default true,
  last_location jsonb,
  last_location_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists core.field_visits (
  id uuid primary key default gen_random_uuid(),
  app_id uuid not null references core.apps(id) on delete restrict,
  assigned_user_id uuid references core.field_workers(user_id) on delete set null,
  created_by uuid not null references auth.users(id) on delete restrict,
  visit_type text not null
    check (visit_type in ('lead', 'onboarding', 'verification', 'training', 'support', 'audit', 'collection', 'other')),
  entity_schema text,
  entity_table text,
  entity_id text,
  contact_name text,
  contact_phone text,
  business_name text,
  province text not null,
  city text not null,
  address text,
  planned_for timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  status text not null default 'planned'
    check (status in ('planned', 'assigned', 'in_progress', 'completed', 'failed', 'cancelled', 'reschedule_required')),
  outcome text,
  checklist jsonb not null default '[]'::jsonb,
  evidence jsonb not null default '[]'::jsonb,
  start_location jsonb,
  end_location jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists core.field_visit_events (
  id bigint generated always as identity primary key,
  visit_id uuid not null references core.field_visits(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  location jsonb,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_support_cases_app_status
  on core.support_cases(app_id, status, priority, created_at desc);
create index if not exists idx_support_cases_requester
  on core.support_cases(requester_user_id, created_at desc);
create index if not exists idx_support_cases_assignee
  on core.support_cases(assigned_user_id, status, created_at desc);
create index if not exists idx_support_messages_case
  on core.support_case_messages(case_id, created_at);
create index if not exists idx_marketing_campaign_status
  on core.marketing_campaigns(status, scheduled_at);
create index if not exists idx_marketing_delivery_campaign
  on core.marketing_deliveries(campaign_id, status, channel);
create index if not exists idx_field_visits_app
  on core.field_visits(app_id, status, planned_for);
create index if not exists idx_field_visits_worker
  on core.field_visits(assigned_user_id, status, planned_for);
create or replace function core.staff_can_access_app(
  p_user_id uuid,
  p_app_id uuid,
  p_manage boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = core, public
as $$
  select
    core.has_role(p_user_id, array['platform_owner', 'platform_admin'])
    or exists (
      select 1 from core.staff_app_scopes s
      where s.staff_user_id = p_user_id
        and s.app_id = p_app_id
        and s.can_read
        and (not p_manage or s.can_manage)
        and s.starts_at <= now()
        and (s.ends_at is null or s.ends_at > now())
    );
$$;
create or replace function core.create_support_case(
  p_app_slug text,
  p_subject text,
  p_description text,
  p_category text default 'general',
  p_priority text default 'normal',
  p_entity_schema text default null,
  p_entity_table text default null,
  p_entity_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = core, public
as $$
declare
  v_app_id uuid;
  v_case_id uuid;
begin
  select id into strict v_app_id from core.apps
  where slug = p_app_slug and is_active;

  insert into core.support_cases (
    app_id, requester_user_id, subject, description, category, priority,
    entity_schema, entity_table, entity_id
  ) values (
    v_app_id, auth.uid(), p_subject, p_description, p_category, p_priority,
    p_entity_schema, p_entity_table, p_entity_id
  ) returning id into v_case_id;

  insert into core.support_case_events(case_id, actor_user_id, event_type, new_value)
  values (v_case_id, auth.uid(), 'case_created',
          jsonb_build_object('status', 'open', 'priority', p_priority));
  return v_case_id;
end;
$$;
create or replace function core.add_support_message(
  p_case_id uuid,
  p_body text,
  p_is_internal boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = core, public
as $$
declare
  v_case core.support_cases%rowtype;
  v_message_id uuid;
  v_is_staff boolean;
begin
  select * into strict v_case from core.support_cases where id = p_case_id;
  v_is_staff := core.has_permission(auth.uid(), 'support.case.manage');

  if not v_is_staff and v_case.requester_user_id is distinct from auth.uid() then
    raise exception 'support_case_access_denied';
  end if;
  if p_is_internal and not v_is_staff then
    raise exception 'internal_message_requires_staff';
  end if;

  insert into core.support_case_messages(
    case_id, author_user_id, author_type, body, is_internal
  ) values (
    p_case_id, auth.uid(), case when v_is_staff then 'staff' else 'customer' end,
    p_body, p_is_internal
  ) returning id into v_message_id;

  update core.support_cases
  set updated_at = now(),
      first_response_at = case
        when v_is_staff then coalesce(first_response_at, now())
        else first_response_at
      end
  where id = p_case_id;
  return v_message_id;
end;
$$;
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'staff_profiles', 'staff_app_scopes', 'support_cases',
    'support_case_messages', 'support_case_events', 'marketing_campaigns',
    'marketing_campaign_apps', 'marketing_deliveries', 'field_workers',
    'field_visits', 'field_visit_events'
  ]
  loop
    execute format('alter table core.%I enable row level security', v_table);
  end loop;
end;
$$;
drop policy if exists support_cases_requester_read on core.support_cases;
create policy support_cases_requester_read on core.support_cases
for select to authenticated
using (
  requester_user_id = auth.uid()
  or (
    core.has_permission(auth.uid(), 'support.case.read')
    and core.staff_can_access_app(auth.uid(), app_id, false)
  )
);
drop policy if exists support_cases_staff_manage on core.support_cases;
create policy support_cases_staff_manage on core.support_cases
for update to authenticated
using (
  core.has_permission(auth.uid(), 'support.case.manage')
  and core.staff_can_access_app(auth.uid(), app_id, true)
)
with check (
  core.has_permission(auth.uid(), 'support.case.manage')
  and core.staff_can_access_app(auth.uid(), app_id, true)
);
drop policy if exists support_messages_read on core.support_case_messages;
create policy support_messages_read on core.support_case_messages
for select to authenticated
using (exists (
  select 1 from core.support_cases c
  where c.id = support_case_messages.case_id
    and (
      (c.requester_user_id = auth.uid() and not support_case_messages.is_internal)
      or (
        core.has_permission(auth.uid(), 'support.case.read')
        and core.staff_can_access_app(auth.uid(), c.app_id, false)
      )
    )
));
drop policy if exists marketing_staff_access on core.marketing_campaigns;
create policy marketing_staff_access on core.marketing_campaigns
for select to authenticated
using (core.has_permission(auth.uid(), 'marketing.campaign.read'));
drop policy if exists marketing_staff_manage on core.marketing_campaigns;
create policy marketing_staff_manage on core.marketing_campaigns
for all to authenticated
using (core.has_permission(auth.uid(), 'marketing.campaign.manage'))
with check (core.has_permission(auth.uid(), 'marketing.campaign.manage'));
drop policy if exists field_visits_worker_read on core.field_visits;
create policy field_visits_worker_read on core.field_visits
for select to authenticated
using (
  assigned_user_id = auth.uid()
  or (
    core.has_permission(auth.uid(), 'field.visit.manage')
    and core.staff_can_access_app(auth.uid(), app_id, false)
  )
);
drop policy if exists field_visits_staff_manage on core.field_visits;
create policy field_visits_staff_manage on core.field_visits
for all to authenticated
using (
  core.has_permission(auth.uid(), 'field.visit.manage')
  and core.staff_can_access_app(auth.uid(), app_id, true)
)
with check (
  core.has_permission(auth.uid(), 'field.visit.manage')
  and core.staff_can_access_app(auth.uid(), app_id, true)
);
grant select on core.staff_profiles, core.staff_app_scopes,
  core.support_cases, core.support_case_messages, core.support_case_events,
  core.marketing_campaigns, core.marketing_campaign_apps,
  core.marketing_deliveries, core.field_workers, core.field_visits,
  core.field_visit_events to authenticated;
grant update on core.support_cases to authenticated;
grant insert, update, delete on core.marketing_campaigns,
  core.marketing_campaign_apps to authenticated;
grant insert, update on core.field_visits to authenticated;
grant all privileges on all tables in schema core to service_role;
grant usage, select on all sequences in schema core to authenticated, service_role;
grant execute on function core.staff_can_access_app(uuid, uuid, boolean)
  to authenticated, service_role;
grant execute on function core.create_support_case(text, text, text, text, text, text, text, text)
  to authenticated, service_role;
grant execute on function core.add_support_message(uuid, text, boolean)
  to authenticated, service_role;
notify pgrst, 'reload schema';
commit;
