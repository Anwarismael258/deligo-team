begin;
create table if not exists comunhao.organizations (
  id uuid primary key,
  name text not null,
  legal_name text,
  code text not null unique,
  owner_user_id uuid references auth.users(id) on delete set null,
  phone text,
  email text,
  country text not null default 'Mozambique',
  province text,
  city text,
  primary_color text,
  logo_url text,
  settings jsonb not null default '{}'::jsonb,
  status text not null default 'active'
    check (status in ('active', 'suspended', 'archived')),
  legacy_source text not null default 'comunhao',
  legacy_owner_profile_id uuid,
  migration_batch text,
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists comunhao.churches (
  id uuid primary key,
  organization_id uuid references comunhao.organizations(id) on delete set null,
  parent_church_id uuid references comunhao.churches(id) on delete set null,
  owner_user_id uuid references auth.users(id) on delete set null,
  name text not null,
  slug text not null unique,
  unit_type text not null default 'headquarters',
  unit_code text,
  app_name text,
  tagline text,
  hero_title text,
  hero_subtitle text,
  logo_url text,
  primary_color text,
  secondary_color text,
  phone text,
  email text,
  country text not null default 'Mozambique',
  province text,
  city text,
  district text,
  neighborhood text,
  address text,
  latitude numeric(10,7),
  longitude numeric(10,7),
  default_currency text not null default 'MZN',
  join_code text,
  capacity integer,
  settings jsonb not null default '{}'::jsonb,
  status text not null default 'active'
    check (status in ('active', 'pending', 'suspended', 'archived')),
  legacy_source text not null default 'comunhao',
  legacy_owner_profile_id uuid,
  migration_batch text,
  is_demo boolean not null default false,
  opened_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists comunhao.memberships (
  id uuid primary key,
  church_id uuid not null references comunhao.churches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member',
  status text not null default 'active'
    check (status in ('pending', 'active', 'inactive', 'transferred', 'suspended')),
  member_code text,
  birth_date date,
  baptism_date date,
  entry_date date,
  gender text,
  neighborhood text,
  ministry_id uuid,
  permissions text[] not null default '{}'::text[],
  legacy_profile_id uuid not null,
  legacy_membership_id uuid not null,
  metadata jsonb not null default '{}'::jsonb,
  joined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (church_id, user_id),
  unique (legacy_membership_id)
);
alter table comunhao.organizations
  add column if not exists migration_batch text;
alter table comunhao.churches
  add column if not exists migration_batch text;
comment on table comunhao.organizations is 'Canonical Comunhao church organizations migrated from the legacy backend.';
comment on table comunhao.churches is 'Canonical Comunhao church units. Legacy UUIDs are preserved.';
comment on table comunhao.memberships is 'Church-scoped membership linked to the canonical platform Auth user.';
create index if not exists idx_comunhao_organizations_owner
  on comunhao.organizations (owner_user_id);
create index if not exists idx_comunhao_churches_organization
  on comunhao.churches (organization_id, status);
create index if not exists idx_comunhao_churches_parent
  on comunhao.churches (parent_church_id);
create index if not exists idx_comunhao_memberships_user
  on comunhao.memberships (user_id, status);
create index if not exists idx_comunhao_memberships_church
  on comunhao.memberships (church_id, role, status);
create index if not exists idx_comunhao_memberships_legacy_profile
  on comunhao.memberships (legacy_profile_id);
create or replace function comunhao.has_church_role(
  p_church_id uuid,
  p_user_id uuid,
  p_roles text[]
)
returns boolean
language sql
stable
security definer
set search_path = comunhao, core, public
as $$
  select
    core.is_platform_admin(p_user_id)
    or exists (
      select 1
      from comunhao.churches c
      where c.id = p_church_id
        and c.owner_user_id = p_user_id
    )
    or exists (
      select 1
      from comunhao.memberships m
      where m.church_id = p_church_id
        and m.user_id = p_user_id
        and m.status = 'active'
        and m.role = any (p_roles)
    );
$$;
create or replace function comunhao.is_church_member(
  p_church_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = comunhao, core, public
as $$
  select
    core.is_platform_admin(p_user_id)
    or exists (
      select 1
      from comunhao.churches c
      where c.id = p_church_id
        and c.owner_user_id = p_user_id
    )
    or exists (
      select 1
      from comunhao.memberships m
      where m.church_id = p_church_id
        and m.user_id = p_user_id
        and m.status = 'active'
    );
$$;
drop trigger if exists trg_comunhao_organizations_touch_updated_at on comunhao.organizations;
create trigger trg_comunhao_organizations_touch_updated_at
before update on comunhao.organizations
for each row execute function public.touch_updated_at();
drop trigger if exists trg_comunhao_churches_touch_updated_at on comunhao.churches;
create trigger trg_comunhao_churches_touch_updated_at
before update on comunhao.churches
for each row execute function public.touch_updated_at();
drop trigger if exists trg_comunhao_memberships_touch_updated_at on comunhao.memberships;
create trigger trg_comunhao_memberships_touch_updated_at
before update on comunhao.memberships
for each row execute function public.touch_updated_at();
alter table comunhao.organizations enable row level security;
alter table comunhao.churches enable row level security;
alter table comunhao.memberships enable row level security;
drop policy if exists comunhao_organizations_select_member_or_admin on comunhao.organizations;
create policy comunhao_organizations_select_member_or_admin
on comunhao.organizations
for select
to authenticated
using (
  owner_user_id = auth.uid()
  or core.is_platform_admin(auth.uid())
  or exists (
    select 1
    from comunhao.churches c
    join comunhao.memberships m on m.church_id = c.id
    where c.organization_id = organizations.id
      and m.user_id = auth.uid()
      and m.status = 'active'
  )
);
drop policy if exists comunhao_organizations_update_owner_or_admin on comunhao.organizations;
create policy comunhao_organizations_update_owner_or_admin
on comunhao.organizations
for update
to authenticated
using (owner_user_id = auth.uid() or core.is_platform_admin(auth.uid()))
with check (owner_user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists comunhao_churches_select_member_or_admin on comunhao.churches;
create policy comunhao_churches_select_member_or_admin
on comunhao.churches
for select
to authenticated
using (comunhao.is_church_member(id, auth.uid()));
drop policy if exists comunhao_churches_update_leader_or_admin on comunhao.churches;
create policy comunhao_churches_update_leader_or_admin
on comunhao.churches
for update
to authenticated
using (
  comunhao.has_church_role(
    id,
    auth.uid(),
    array['pastor', 'church_admin', 'organization_admin']
  )
)
with check (
  comunhao.has_church_role(
    id,
    auth.uid(),
    array['pastor', 'church_admin', 'organization_admin']
  )
);
drop policy if exists comunhao_memberships_select_self_or_leader on comunhao.memberships;
create policy comunhao_memberships_select_self_or_leader
on comunhao.memberships
for select
to authenticated
using (
  user_id = auth.uid()
  or comunhao.has_church_role(
    church_id,
    auth.uid(),
    array['pastor', 'church_admin', 'organization_admin', 'secretary']
  )
);
drop policy if exists comunhao_memberships_manage_leader on comunhao.memberships;
create policy comunhao_memberships_manage_leader
on comunhao.memberships
for all
to authenticated
using (
  comunhao.has_church_role(
    church_id,
    auth.uid(),
    array['pastor', 'church_admin', 'organization_admin']
  )
)
with check (
  comunhao.has_church_role(
    church_id,
    auth.uid(),
    array['pastor', 'church_admin', 'organization_admin']
  )
);
grant select on comunhao.organizations, comunhao.churches, comunhao.memberships to authenticated;
grant update on comunhao.organizations, comunhao.churches to authenticated;
grant insert, update, delete on comunhao.memberships to authenticated;
grant all privileges on comunhao.organizations, comunhao.churches, comunhao.memberships to service_role;
grant execute on function comunhao.has_church_role(uuid, uuid, text[]) to authenticated, service_role;
grant execute on function comunhao.is_church_member(uuid, uuid) to authenticated, service_role;
insert into core.roles (slug, name, scope, app_id, description)
select
  seed.slug,
  seed.name,
  'app',
  app.id,
  seed.description
from core.apps app
cross join (
  values
    ('comunhao_super_admin', 'Comunhao Super Admin', 'Platform administration inside Comunhao.'),
    ('comunhao_support_agent', 'Comunhao Support Agent', 'Support operations inside Comunhao.'),
    ('comunhao_pastor', 'Comunhao Pastor', 'Pastoral leadership inside a church.'),
    ('comunhao_church_admin', 'Comunhao Church Admin', 'Administrative leadership inside a church.')
) as seed(slug, name, description)
where app.slug = 'comunhao'
on conflict (slug) do update
set
  name = excluded.name,
  scope = excluded.scope,
  app_id = excluded.app_id,
  description = excluded.description,
  updated_at = now();
commit;
