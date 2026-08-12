-- DeliGo Triunfal Platform
-- Phase 1 blueprint: shared schemas and core identity layer.
-- This migration is intentionally additive and does not alter legacy
-- public tables such as orders, restaurants, deliveries, couriers,
-- wallets or payments.

begin;
create schema if not exists core;
create schema if not exists payments;
create schema if not exists deligo;
create schema if not exists comunhao;
create schema if not exists sarca;
create schema if not exists taomoz;
comment on schema core is 'Shared platform identity, access control, audit and notification layer for DeliGo Triunfal Platform.';
comment on schema payments is 'Shared financial layer for wallet accounts, ledger, payments, payouts, refunds, escrow and reconciliation.';
comment on schema deligo is 'Logical schema reserved for DeliGo module views and future module tables.';
comment on schema comunhao is 'Logical schema reserved for Comunhao module tables and views.';
comment on schema sarca is 'Logical schema reserved for Sarca module tables and views.';
comment on schema taomoz is 'Logical schema reserved for Tao Moz module tables and views.';
grant usage on schema core to authenticated, service_role;
grant usage on schema payments to authenticated, service_role;
grant usage on schema deligo to authenticated, service_role;
grant usage on schema comunhao to authenticated, service_role;
grant usage on schema sarca to authenticated, service_role;
grant usage on schema taomoz to authenticated, service_role;
create table if not exists core.apps (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  display_name text not null,
  description text,
  runtime_type text not null default 'mobile'
    check (runtime_type in ('mobile', 'web', 'admin', 'hybrid')),
  module_schema text not null
    check (module_schema in ('deligo', 'comunhao', 'sarca', 'taomoz')),
  legacy_project_ref text,
  is_active boolean not null default true,
  is_public boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table core.apps is 'Registry of products that belong to the DeliGo Triunfal Platform.';
comment on column core.apps.slug is 'Stable application identifier used by policies, configs and migration scripts.';
comment on column core.apps.legacy_project_ref is 'Current Supabase project ref for the legacy backend during the transition phase.';
create table if not exists core.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  primary_phone text,
  primary_email text,
  full_name text,
  display_name text,
  avatar_url text,
  locale text not null default 'pt_MZ',
  timezone text not null default 'Africa/Maputo',
  country_code text not null default 'MZ',
  default_app_id uuid references core.apps(id) on delete set null,
  profile_status text not null default 'active'
    check (profile_status in ('active', 'pending', 'suspended', 'disabled', 'deleted')),
  marketing_opt_in boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table core.profiles is 'Canonical cross-product profile keyed by auth.users.id.';
comment on column core.profiles.user_id is 'Canonical platform user id. auth.users remains the source of truth for authentication.';
create table if not exists core.user_app_memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  app_id uuid not null references core.apps(id) on delete cascade,
  membership_status text not null default 'active'
    check (membership_status in ('invited', 'active', 'suspended', 'disabled')),
  joined_at timestamptz not null default now(),
  last_seen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, app_id)
);
comment on table core.user_app_memberships is 'Membership registry that links a canonical user to one or more products in the platform.';
create table if not exists core.roles (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  scope text not null default 'platform'
    check (scope in ('platform', 'app')),
  app_id uuid references core.apps(id) on delete cascade,
  description text,
  is_system boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table core.roles is 'Role catalog for platform-wide and app-specific RBAC.';
create table if not exists core.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  module_scope text not null default 'platform'
    check (module_scope in ('platform', 'core', 'payments', 'deligo', 'comunhao', 'sarca', 'taomoz')),
  description text,
  created_at timestamptz not null default now()
);
comment on table core.permissions is 'Permission catalog consumed by role_permissions and future authorization layers.';
create table if not exists core.role_permissions (
  role_id uuid not null references core.roles(id) on delete cascade,
  permission_id uuid not null references core.permissions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);
comment on table core.role_permissions is 'Many-to-many mapping between roles and permissions.';
create table if not exists core.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null references core.roles(id) on delete cascade,
  assigned_by uuid references auth.users(id) on delete set null,
  assignment_reason text,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, role_id)
);
comment on table core.user_roles is 'Active role assignments for users. A user can receive platform roles and app roles.';
create table if not exists core.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  app_id uuid references core.apps(id) on delete set null,
  entity_schema text not null,
  entity_table text not null,
  entity_id text not null,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  ip_address inet,
  user_agent text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
comment on table core.audit_logs is 'Cross-platform audit trail for privileged and important domain actions.';
create table if not exists core.notification_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  app_id uuid not null references core.apps(id) on delete cascade,
  push_enabled boolean not null default true,
  email_enabled boolean not null default true,
  sms_enabled boolean not null default true,
  marketing_enabled boolean not null default false,
  quiet_hours jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, app_id)
);
comment on table core.notification_preferences is 'Per-user and per-app notification settings.';
create table if not exists core.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  app_id uuid references core.apps(id) on delete set null,
  device_type text not null
    check (device_type in ('android', 'ios', 'web', 'desktop', 'unknown')),
  push_provider text
    check (push_provider in ('fcm', 'apns', 'web_push', 'none')),
  push_token text,
  device_label text,
  app_version text,
  os_version text,
  last_seen_at timestamptz,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table core.user_devices is 'Normalized device registry shared by mobile and web products.';
create table if not exists core.legacy_user_links (
  id uuid primary key default gen_random_uuid(),
  canonical_user_id uuid not null references auth.users(id) on delete cascade,
  source_app_slug text not null,
  source_project_ref text,
  legacy_user_id uuid not null,
  legacy_profile_table text not null default 'public.profiles',
  migration_status text not null default 'linked'
    check (migration_status in ('linked', 'pending', 'conflict', 'migrated', 'ignored')),
  identifiers jsonb not null default '{}'::jsonb,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_app_slug, legacy_user_id)
);
comment on table core.legacy_user_links is 'Crosswalk between legacy backend user ids and canonical platform auth users.';
create index if not exists idx_core_apps_active on core.apps (is_active);
create index if not exists idx_core_profiles_phone on core.profiles (lower(primary_phone));
create index if not exists idx_core_profiles_email on core.profiles (lower(primary_email));
create index if not exists idx_core_user_app_memberships_user on core.user_app_memberships (user_id, membership_status);
create index if not exists idx_core_roles_scope on core.roles (scope, app_id);
create index if not exists idx_core_permissions_scope on core.permissions (module_scope);
create index if not exists idx_core_user_roles_user on core.user_roles (user_id, role_id);
create index if not exists idx_core_audit_logs_actor on core.audit_logs (actor_user_id, occurred_at desc);
create index if not exists idx_core_audit_logs_entity on core.audit_logs (entity_schema, entity_table, entity_id, occurred_at desc);
create index if not exists idx_core_notification_preferences_user on core.notification_preferences (user_id, app_id);
create index if not exists idx_core_user_devices_user on core.user_devices (user_id, is_active);
create unique index if not exists idx_core_user_devices_token
  on core.user_devices (app_id, push_provider, push_token)
  where push_token is not null;
create index if not exists idx_core_legacy_user_links_user on core.legacy_user_links (canonical_user_id, source_app_slug);
create or replace function core.has_role(p_user_id uuid, p_role_slugs text[])
returns boolean
language sql
stable
security definer
set search_path = core, public
as $$
  select exists (
    select 1
    from core.user_roles ur
    join core.roles r on r.id = ur.role_id
    where ur.user_id = p_user_id
      and (ur.ends_at is null or ur.ends_at > now())
      and r.slug = any (p_role_slugs)
  );
$$;
comment on function core.has_role(uuid, text[]) is 'Security-definer helper used by policies to resolve active platform or app roles.';
create or replace function core.is_platform_admin(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = core, public
as $$
  select core.has_role(
    p_user_id,
    array['platform_owner', 'platform_admin']
  );
$$;
create or replace function core.is_platform_auditor(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = core, public
as $$
  select core.has_role(
    p_user_id,
    array['platform_owner', 'platform_admin', 'platform_auditor']
  );
$$;
create or replace function core.sync_profile_from_auth_user()
returns trigger
language plpgsql
security definer
set search_path = auth, core, public
as $$
declare
  v_full_name text;
begin
  v_full_name := coalesce(
    nullif(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'name', ''),
    split_part(coalesce(new.email, new.phone, new.id::text), '@', 1)
  );

  insert into core.profiles (
    user_id,
    primary_phone,
    primary_email,
    full_name,
    display_name,
    avatar_url
  )
  values (
    new.id,
    coalesce(new.phone, nullif(new.raw_user_meta_data ->> 'phone', '')),
    new.email,
    v_full_name,
    v_full_name,
    nullif(new.raw_user_meta_data ->> 'avatar_url', '')
  )
  on conflict (user_id) do update
  set
    primary_phone = coalesce(excluded.primary_phone, core.profiles.primary_phone),
    primary_email = coalesce(excluded.primary_email, core.profiles.primary_email),
    full_name = coalesce(excluded.full_name, core.profiles.full_name),
    display_name = coalesce(excluded.display_name, core.profiles.display_name),
    avatar_url = coalesce(excluded.avatar_url, core.profiles.avatar_url),
    updated_at = now();

  return new;
end;
$$;
comment on function core.sync_profile_from_auth_user() is 'Maintains the canonical core.profiles row whenever auth.users changes.';
drop trigger if exists trg_core_apps_touch_updated_at on core.apps;
create trigger trg_core_apps_touch_updated_at
before update on core.apps
for each row execute function public.touch_updated_at();
drop trigger if exists trg_core_profiles_touch_updated_at on core.profiles;
create trigger trg_core_profiles_touch_updated_at
before update on core.profiles
for each row execute function public.touch_updated_at();
drop trigger if exists trg_core_user_app_memberships_touch_updated_at on core.user_app_memberships;
create trigger trg_core_user_app_memberships_touch_updated_at
before update on core.user_app_memberships
for each row execute function public.touch_updated_at();
drop trigger if exists trg_core_roles_touch_updated_at on core.roles;
create trigger trg_core_roles_touch_updated_at
before update on core.roles
for each row execute function public.touch_updated_at();
drop trigger if exists trg_core_user_roles_touch_updated_at on core.user_roles;
create trigger trg_core_user_roles_touch_updated_at
before update on core.user_roles
for each row execute function public.touch_updated_at();
drop trigger if exists trg_core_notification_preferences_touch_updated_at on core.notification_preferences;
create trigger trg_core_notification_preferences_touch_updated_at
before update on core.notification_preferences
for each row execute function public.touch_updated_at();
drop trigger if exists trg_core_user_devices_touch_updated_at on core.user_devices;
create trigger trg_core_user_devices_touch_updated_at
before update on core.user_devices
for each row execute function public.touch_updated_at();
drop trigger if exists trg_core_legacy_user_links_touch_updated_at on core.legacy_user_links;
create trigger trg_core_legacy_user_links_touch_updated_at
before update on core.legacy_user_links
for each row execute function public.touch_updated_at();
drop trigger if exists trg_core_sync_profile_from_auth_user on auth.users;
create trigger trg_core_sync_profile_from_auth_user
after insert or update of email, phone, raw_user_meta_data on auth.users
for each row execute function core.sync_profile_from_auth_user();
alter table core.apps enable row level security;
alter table core.profiles enable row level security;
alter table core.user_app_memberships enable row level security;
alter table core.roles enable row level security;
alter table core.permissions enable row level security;
alter table core.role_permissions enable row level security;
alter table core.user_roles enable row level security;
alter table core.audit_logs enable row level security;
alter table core.notification_preferences enable row level security;
alter table core.user_devices enable row level security;
alter table core.legacy_user_links enable row level security;
drop policy if exists core_apps_read_authenticated on core.apps;
create policy core_apps_read_authenticated
on core.apps
for select
to authenticated
using (true);
drop policy if exists core_profiles_select_self_or_admin on core.profiles;
create policy core_profiles_select_self_or_admin
on core.profiles
for select
to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists core_profiles_update_self_or_admin on core.profiles;
create policy core_profiles_update_self_or_admin
on core.profiles
for update
to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()))
with check (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists core_user_app_memberships_select_self_or_admin on core.user_app_memberships;
create policy core_user_app_memberships_select_self_or_admin
on core.user_app_memberships
for select
to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists core_user_app_memberships_update_self_or_admin on core.user_app_memberships;
create policy core_user_app_memberships_update_self_or_admin
on core.user_app_memberships
for update
to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()))
with check (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists core_user_app_memberships_insert_admin_only on core.user_app_memberships;
create policy core_user_app_memberships_insert_admin_only
on core.user_app_memberships
for insert
to authenticated
with check (core.is_platform_admin(auth.uid()));
drop policy if exists core_user_app_memberships_delete_admin_only on core.user_app_memberships;
create policy core_user_app_memberships_delete_admin_only
on core.user_app_memberships
for delete
to authenticated
using (core.is_platform_admin(auth.uid()));
drop policy if exists core_roles_read_authenticated on core.roles;
create policy core_roles_read_authenticated
on core.roles
for select
to authenticated
using (true);
drop policy if exists core_permissions_read_authenticated on core.permissions;
create policy core_permissions_read_authenticated
on core.permissions
for select
to authenticated
using (true);
drop policy if exists core_role_permissions_read_authenticated on core.role_permissions;
create policy core_role_permissions_read_authenticated
on core.role_permissions
for select
to authenticated
using (true);
drop policy if exists core_user_roles_select_self_or_admin on core.user_roles;
create policy core_user_roles_select_self_or_admin
on core.user_roles
for select
to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists core_user_roles_insert_admin_only on core.user_roles;
create policy core_user_roles_insert_admin_only
on core.user_roles
for insert
to authenticated
with check (core.is_platform_admin(auth.uid()));
drop policy if exists core_user_roles_update_admin_only on core.user_roles;
create policy core_user_roles_update_admin_only
on core.user_roles
for update
to authenticated
using (core.is_platform_admin(auth.uid()))
with check (core.is_platform_admin(auth.uid()));
drop policy if exists core_user_roles_delete_admin_only on core.user_roles;
create policy core_user_roles_delete_admin_only
on core.user_roles
for delete
to authenticated
using (core.is_platform_admin(auth.uid()));
drop policy if exists core_audit_logs_select_admin_or_auditor on core.audit_logs;
create policy core_audit_logs_select_admin_or_auditor
on core.audit_logs
for select
to authenticated
using (core.is_platform_auditor(auth.uid()));
drop policy if exists core_notification_preferences_select_self_or_admin on core.notification_preferences;
create policy core_notification_preferences_select_self_or_admin
on core.notification_preferences
for select
to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists core_notification_preferences_insert_self_or_admin on core.notification_preferences;
create policy core_notification_preferences_insert_self_or_admin
on core.notification_preferences
for insert
to authenticated
with check (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists core_notification_preferences_update_self_or_admin on core.notification_preferences;
create policy core_notification_preferences_update_self_or_admin
on core.notification_preferences
for update
to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()))
with check (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists core_notification_preferences_delete_self_or_admin on core.notification_preferences;
create policy core_notification_preferences_delete_self_or_admin
on core.notification_preferences
for delete
to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists core_user_devices_select_self_or_admin on core.user_devices;
create policy core_user_devices_select_self_or_admin
on core.user_devices
for select
to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists core_user_devices_insert_self_or_admin on core.user_devices;
create policy core_user_devices_insert_self_or_admin
on core.user_devices
for insert
to authenticated
with check (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists core_user_devices_update_self_or_admin on core.user_devices;
create policy core_user_devices_update_self_or_admin
on core.user_devices
for update
to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()))
with check (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists core_user_devices_delete_self_or_admin on core.user_devices;
create policy core_user_devices_delete_self_or_admin
on core.user_devices
for delete
to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists core_legacy_user_links_select_admin_or_auditor on core.legacy_user_links;
create policy core_legacy_user_links_select_admin_or_auditor
on core.legacy_user_links
for select
to authenticated
using (core.is_platform_auditor(auth.uid()));
grant select on core.apps to authenticated;
grant select, update on core.profiles to authenticated;
grant select, insert, update, delete on core.user_app_memberships to authenticated;
grant select, insert, update, delete on core.user_roles to authenticated;
grant select on core.roles, core.permissions, core.role_permissions, core.audit_logs, core.legacy_user_links to authenticated;
grant select, insert, update, delete on core.notification_preferences, core.user_devices to authenticated;
grant all privileges on all tables in schema core to service_role;
grant execute on function core.has_role(uuid, text[]) to authenticated, service_role;
grant execute on function core.is_platform_admin(uuid) to authenticated, service_role;
grant execute on function core.is_platform_auditor(uuid) to authenticated, service_role;
insert into core.apps (
  slug,
  name,
  display_name,
  description,
  runtime_type,
  module_schema,
  legacy_project_ref,
  is_active,
  is_public
)
values
  (
    'deligo',
    'DeliGo',
    'DeliGo',
    'Delivery, commerce, couriers, payments and future operational modules.',
    'hybrid',
    'deligo',
    'gfkptccbalpacyypptgl',
    true,
    true
  ),
  (
    'comunhao',
    'Comunhao',
    'Comunhao',
    'Church, community, events, ministries and pastoral workflows.',
    'mobile',
    'comunhao',
    'dxofxuajsrocbxdmekfx',
    true,
    false
  ),
  (
    'sarca',
    'Sarca',
    'Sarca',
    'Mobility, drivers, passengers, trips and wallet-enabled transport flows.',
    'hybrid',
    'sarca',
    'oqyjzzkdcizwnkjypujs',
    true,
    false
  ),
  (
    'taomoz',
    'Tao Moz',
    'Tao Moz',
    'Marketplace, sellers, communities, content and logistics.',
    'web',
    'taomoz',
    'fxiqvqswiupouuhxeqoa',
    true,
    true
  )
on conflict (slug) do update
set
  name = excluded.name,
  display_name = excluded.display_name,
  description = excluded.description,
  runtime_type = excluded.runtime_type,
  module_schema = excluded.module_schema,
  legacy_project_ref = excluded.legacy_project_ref,
  is_active = excluded.is_active,
  is_public = excluded.is_public,
  updated_at = now();
insert into core.roles (slug, name, scope, app_id, description)
select
  seed.slug,
  seed.name,
  seed.scope,
  app.id,
  seed.description
from (
  values
    ('platform_owner', 'Platform Owner', 'platform', null, 'Full control over the DeliGo Triunfal Platform.'),
    ('platform_admin', 'Platform Admin', 'platform', null, 'Operational administration across the platform.'),
    ('platform_auditor', 'Platform Auditor', 'platform', null, 'Read-only access to audit and reconciliation workflows.'),
    ('deligo_customer', 'DeliGo Customer', 'app', 'deligo', 'Consumer account for DeliGo.'),
    ('deligo_restaurant', 'DeliGo Restaurant', 'app', 'deligo', 'Restaurant operator inside DeliGo.'),
    ('deligo_courier', 'DeliGo Courier', 'app', 'deligo', 'Courier or delivery agent inside DeliGo.'),
    ('comunhao_member', 'Comunhao Member', 'app', 'comunhao', 'Member account inside Comunhao.'),
    ('comunhao_admin', 'Comunhao Admin', 'app', 'comunhao', 'Church or platform operator inside Comunhao.'),
    ('sarca_passenger', 'Sarca Passenger', 'app', 'sarca', 'Passenger account inside Sarca.'),
    ('sarca_driver', 'Sarca Driver', 'app', 'sarca', 'Driver account inside Sarca.'),
    ('taomoz_buyer', 'Tao Moz Buyer', 'app', 'taomoz', 'Buyer account inside Tao Moz.'),
    ('taomoz_seller', 'Tao Moz Seller', 'app', 'taomoz', 'Seller account inside Tao Moz.')
) as seed(slug, name, scope, app_slug, description)
left join core.apps app on app.slug = seed.app_slug
on conflict (slug) do update
set
  name = excluded.name,
  scope = excluded.scope,
  app_id = excluded.app_id,
  description = excluded.description,
  updated_at = now();
insert into core.permissions (code, name, module_scope, description)
values
  ('core.profile.read_self', 'Read own profile', 'core', 'Allows a user to read the canonical platform profile.'),
  ('core.profile.update_self', 'Update own profile', 'core', 'Allows a user to update the canonical platform profile.'),
  ('core.membership.read_self', 'Read own app memberships', 'core', 'Allows a user to inspect which apps are linked to the account.'),
  ('core.device.manage_self', 'Manage own devices', 'core', 'Allows a user to manage personal device registrations.'),
  ('core.notification.manage_self', 'Manage own notifications', 'core', 'Allows a user to manage notification preferences.'),
  ('payments.wallet.read_self', 'Read own wallets', 'payments', 'Allows a user to read wallet accounts and ledger entries.'),
  ('payments.method.manage_self', 'Manage own payment methods', 'payments', 'Allows a user to register or update their own payment methods.'),
  ('payments.payout.request_self', 'Request own payout', 'payments', 'Allows a user to request payout from an owned wallet account.'),
  ('platform.audit.read', 'Read audit logs', 'platform', 'Allows access to platform audit and reconciliation read flows.'),
  ('platform.user.manage', 'Manage users and memberships', 'platform', 'Allows privileged management of profiles, roles and memberships.'),
  ('platform.reconcile.manage', 'Manage reconciliation', 'platform', 'Allows privileged financial reconciliation operations.')
on conflict (code) do update
set
  name = excluded.name,
  module_scope = excluded.module_scope,
  description = excluded.description;
insert into core.role_permissions (role_id, permission_id)
select r.id, p.id
from core.roles r
cross join core.permissions p
where r.slug in ('platform_owner', 'platform_admin')
on conflict do nothing;
insert into core.role_permissions (role_id, permission_id)
select r.id, p.id
from core.roles r
join core.permissions p on p.code in ('platform.audit.read', 'payments.wallet.read_self')
where r.slug = 'platform_auditor'
on conflict do nothing;
insert into core.role_permissions (role_id, permission_id)
select r.id, p.id
from core.roles r
join core.permissions p on p.code in (
  'core.profile.read_self',
  'core.profile.update_self',
  'core.membership.read_self',
  'core.device.manage_self',
  'core.notification.manage_self',
  'payments.wallet.read_self',
  'payments.method.manage_self',
  'payments.payout.request_self'
)
where r.slug in (
  'deligo_customer',
  'deligo_restaurant',
  'deligo_courier',
  'comunhao_member',
  'comunhao_admin',
  'sarca_passenger',
  'sarca_driver',
  'taomoz_buyer',
  'taomoz_seller'
)
on conflict do nothing;
insert into core.profiles (
  user_id,
  primary_phone,
  primary_email,
  full_name,
  display_name,
  avatar_url
)
select
  u.id,
  u.phone,
  u.email,
  coalesce(
    nullif(u.raw_user_meta_data ->> 'full_name', ''),
    nullif(u.raw_user_meta_data ->> 'name', ''),
    split_part(coalesce(u.email, u.phone, u.id::text), '@', 1)
  ),
  coalesce(
    nullif(u.raw_user_meta_data ->> 'full_name', ''),
    nullif(u.raw_user_meta_data ->> 'name', ''),
    split_part(coalesce(u.email, u.phone, u.id::text), '@', 1)
  ),
  nullif(u.raw_user_meta_data ->> 'avatar_url', '')
from auth.users u
on conflict (user_id) do update
set
  primary_phone = coalesce(excluded.primary_phone, core.profiles.primary_phone),
  primary_email = coalesce(excluded.primary_email, core.profiles.primary_email),
  full_name = coalesce(excluded.full_name, core.profiles.full_name),
  display_name = coalesce(excluded.display_name, core.profiles.display_name),
  avatar_url = coalesce(excluded.avatar_url, core.profiles.avatar_url),
  updated_at = now();
commit;
