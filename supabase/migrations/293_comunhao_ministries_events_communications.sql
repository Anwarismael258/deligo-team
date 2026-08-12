begin;
create table if not exists comunhao.ministries (
  id uuid primary key,
  church_id uuid not null references comunhao.churches(id) on delete cascade,
  name text not null,
  description text,
  leader_membership_id uuid references comunhao.memberships(id) on delete set null,
  status text not null default 'active'
    check (status in ('active', 'inactive', 'archived')),
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (church_id, name)
);
create table if not exists comunhao.ministry_members (
  id uuid primary key,
  ministry_id uuid not null references comunhao.ministries(id) on delete cascade,
  membership_id uuid not null references comunhao.memberships(id) on delete cascade,
  role text not null default 'member'
    check (role in ('leader', 'assistant', 'member')),
  status text not null default 'active'
    check (status in ('active', 'inactive', 'removed')),
  migration_batch text,
  joined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (ministry_id, membership_id)
);
create table if not exists comunhao.groups (
  id uuid primary key,
  church_id uuid not null references comunhao.churches(id) on delete cascade,
  ministry_id uuid references comunhao.ministries(id) on delete set null,
  name text not null,
  group_type text not null default 'cell',
  description text,
  leader_membership_id uuid references comunhao.memberships(id) on delete set null,
  vice_leader_membership_id uuid references comunhao.memberships(id) on delete set null,
  location text,
  usual_day text,
  usual_time text,
  capacity integer,
  audience text not null default 'members',
  objective text,
  notes text,
  status text not null default 'active',
  color text,
  created_by_user_id uuid references auth.users(id) on delete set null,
  migration_batch text,
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (church_id, name)
);
create table if not exists comunhao.group_members (
  id uuid primary key,
  group_id uuid not null references comunhao.groups(id) on delete cascade,
  membership_id uuid not null references comunhao.memberships(id) on delete cascade,
  role text not null default 'member',
  status text not null default 'active',
  joined_at date not null default current_date,
  ended_at date,
  notes text,
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (group_id, membership_id)
);
create table if not exists comunhao.events (
  id uuid primary key,
  church_id uuid not null references comunhao.churches(id) on delete cascade,
  ministry_id uuid references comunhao.ministries(id) on delete set null,
  recurrence_parent_id uuid references comunhao.events(id) on delete set null,
  title text not null,
  description text,
  category text,
  status text not null default 'published'
    check (status in ('draft', 'scheduled', 'published', 'ongoing', 'completed', 'cancelled', 'postponed', 'archived')),
  visibility text not null default 'members',
  starts_at timestamptz not null,
  ends_at timestamptz,
  timezone text not null default 'Africa/Maputo',
  location_name text,
  address text,
  latitude numeric(10,7),
  longitude numeric(10,7),
  online_url text,
  speaker_name text,
  guest_name text,
  organizer_name text,
  program text,
  requirements text,
  registration_required boolean not null default false,
  registration_deadline timestamptz,
  capacity integer,
  registration_fee_mzn numeric(12,2) not null default 0,
  payment_required boolean not null default false,
  attendance_required boolean not null default false,
  is_public boolean not null default true,
  recurrence_rule text,
  checkin_opens_at timestamptz,
  checkin_closes_at timestamptz,
  cover_image_url text,
  cancellation_reason text,
  responsible_user_id uuid references auth.users(id) on delete set null,
  created_by_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  migration_batch text,
  is_featured boolean not null default false,
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists comunhao.event_occurrences (
  id uuid primary key,
  event_id uuid not null references comunhao.events(id) on delete cascade,
  church_id uuid not null references comunhao.churches(id) on delete cascade,
  occurrence_start_at timestamptz not null,
  occurrence_end_at timestamptz,
  status text not null default 'scheduled',
  checkin_opens_at timestamptz,
  checkin_closes_at timestamptz,
  qr_token_hash text,
  qr_expires_at timestamptz,
  qr_closed_at timestamptz,
  override_title text,
  override_location text,
  cancellation_reason text,
  migration_batch text,
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, occurrence_start_at)
);
create table if not exists comunhao.event_registrations (
  id uuid primary key,
  event_id uuid not null references comunhao.events(id) on delete cascade,
  occurrence_id uuid references comunhao.event_occurrences(id) on delete set null,
  user_id uuid not null references auth.users(id) on delete cascade,
  legacy_profile_id uuid not null,
  status text not null default 'confirmed'
    check (status in ('registered', 'waiting_list', 'confirmed', 'cancelled', 'checked_in', 'no_show')),
  attendee_count integer not null default 1 check (attendee_count > 0),
  special_needs text,
  payment_status text not null default 'not_required',
  cancelled_at timestamptz,
  checked_in_by_user_id uuid references auth.users(id) on delete set null,
  check_in_method text,
  check_out_at timestamptz,
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, user_id)
);
create table if not exists comunhao.announcements (
  id uuid primary key,
  church_id uuid not null references comunhao.churches(id) on delete cascade,
  title text not null,
  body text not null,
  category text not null default 'comunicado',
  audience_type text not null default 'all',
  image_url text,
  attachment_url text,
  publication_status text not null default 'published',
  pinned boolean not null default false,
  notify_members boolean not null default false,
  published_at timestamptz,
  created_by_user_id uuid references auth.users(id) on delete set null,
  migration_batch text,
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists comunhao.communications (
  id uuid primary key,
  church_id uuid not null references comunhao.churches(id) on delete cascade,
  ministry_id uuid references comunhao.ministries(id) on delete set null,
  target_membership_id uuid references comunhao.memberships(id) on delete set null,
  channel text not null default 'push'
    check (channel in ('push', 'sms', 'whatsapp', 'email', 'in_app')),
  audience_type text not null default 'all',
  target_role text,
  title text not null,
  body text not null,
  status text not null default 'draft',
  scheduled_at timestamptz,
  sent_at timestamptz,
  created_by_user_id uuid references auth.users(id) on delete set null,
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_comunhao_ministries_church on comunhao.ministries (church_id, status);
create index if not exists idx_comunhao_ministry_members_membership on comunhao.ministry_members (membership_id);
create index if not exists idx_comunhao_groups_church on comunhao.groups (church_id, status);
create index if not exists idx_comunhao_group_members_membership on comunhao.group_members (membership_id);
create index if not exists idx_comunhao_events_church_start on comunhao.events (church_id, starts_at);
create index if not exists idx_comunhao_event_occurrences_event on comunhao.event_occurrences (event_id, occurrence_start_at);
create index if not exists idx_comunhao_event_registrations_user on comunhao.event_registrations (user_id, status);
create index if not exists idx_comunhao_announcements_church on comunhao.announcements (church_id, published_at desc);
create index if not exists idx_comunhao_communications_church on comunhao.communications (church_id, status);
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'ministries', 'ministry_members', 'groups', 'group_members', 'events',
    'event_occurrences', 'event_registrations', 'announcements', 'communications'
  ]
  loop
    execute format('drop trigger if exists %I on comunhao.%I', 'trg_comunhao_' || v_table || '_touch_updated_at', v_table);
    execute format(
      'create trigger %I before update on comunhao.%I for each row execute function public.touch_updated_at()',
      'trg_comunhao_' || v_table || '_touch_updated_at',
      v_table
    );
    execute format('alter table comunhao.%I enable row level security', v_table);
  end loop;
end;
$$;
drop policy if exists comunhao_ministries_select_member on comunhao.ministries;
create policy comunhao_ministries_select_member on comunhao.ministries
for select to authenticated
using (comunhao.is_church_member(church_id, auth.uid()));
drop policy if exists comunhao_ministries_manage_leader on comunhao.ministries;
create policy comunhao_ministries_manage_leader on comunhao.ministries
for all to authenticated
using (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','ministry_leader']))
with check (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','ministry_leader']));
drop policy if exists comunhao_groups_select_member on comunhao.groups;
create policy comunhao_groups_select_member on comunhao.groups
for select to authenticated
using (comunhao.is_church_member(church_id, auth.uid()));
drop policy if exists comunhao_groups_manage_leader on comunhao.groups;
create policy comunhao_groups_manage_leader on comunhao.groups
for all to authenticated
using (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','cell_leader']))
with check (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','cell_leader']));
drop policy if exists comunhao_events_select_visible on comunhao.events;
create policy comunhao_events_select_visible on comunhao.events
for select to authenticated
using (is_public or comunhao.is_church_member(church_id, auth.uid()));
drop policy if exists comunhao_events_manage_leader on comunhao.events;
create policy comunhao_events_manage_leader on comunhao.events
for all to authenticated
using (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','event_manager']))
with check (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','event_manager']));
drop policy if exists comunhao_announcements_select_member on comunhao.announcements;
create policy comunhao_announcements_select_member on comunhao.announcements
for select to authenticated
using (comunhao.is_church_member(church_id, auth.uid()));
drop policy if exists comunhao_announcements_manage_leader on comunhao.announcements;
create policy comunhao_announcements_manage_leader on comunhao.announcements
for all to authenticated
using (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','communications_manager']))
with check (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','communications_manager']));
drop policy if exists comunhao_communications_select_member on comunhao.communications;
create policy comunhao_communications_select_member on comunhao.communications
for select to authenticated
using (comunhao.is_church_member(church_id, auth.uid()));
drop policy if exists comunhao_communications_manage_leader on comunhao.communications;
create policy comunhao_communications_manage_leader on comunhao.communications
for all to authenticated
using (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','communications_manager']))
with check (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','communications_manager']));
drop policy if exists comunhao_ministry_members_select_church_member on comunhao.ministry_members;
create policy comunhao_ministry_members_select_church_member on comunhao.ministry_members
for select to authenticated
using (
  exists (
    select 1 from comunhao.ministries mi
    where mi.id = ministry_members.ministry_id
      and comunhao.is_church_member(mi.church_id, auth.uid())
  )
);
drop policy if exists comunhao_ministry_members_manage_leader on comunhao.ministry_members;
create policy comunhao_ministry_members_manage_leader on comunhao.ministry_members
for all to authenticated
using (
  exists (
    select 1 from comunhao.ministries mi
    where mi.id = ministry_members.ministry_id
      and comunhao.has_church_role(mi.church_id, auth.uid(), array['pastor','church_admin','organization_admin','ministry_leader'])
  )
)
with check (
  exists (
    select 1 from comunhao.ministries mi
    where mi.id = ministry_members.ministry_id
      and comunhao.has_church_role(mi.church_id, auth.uid(), array['pastor','church_admin','organization_admin','ministry_leader'])
  )
);
drop policy if exists comunhao_group_members_select_church_member on comunhao.group_members;
create policy comunhao_group_members_select_church_member on comunhao.group_members
for select to authenticated
using (
  exists (
    select 1 from comunhao.groups g
    where g.id = group_members.group_id
      and comunhao.is_church_member(g.church_id, auth.uid())
  )
);
drop policy if exists comunhao_group_members_manage_leader on comunhao.group_members;
create policy comunhao_group_members_manage_leader on comunhao.group_members
for all to authenticated
using (
  exists (
    select 1 from comunhao.groups g
    where g.id = group_members.group_id
      and comunhao.has_church_role(g.church_id, auth.uid(), array['pastor','church_admin','organization_admin','cell_leader'])
  )
)
with check (
  exists (
    select 1 from comunhao.groups g
    where g.id = group_members.group_id
      and comunhao.has_church_role(g.church_id, auth.uid(), array['pastor','church_admin','organization_admin','cell_leader'])
  )
);
drop policy if exists comunhao_event_occurrences_select_visible on comunhao.event_occurrences;
create policy comunhao_event_occurrences_select_visible on comunhao.event_occurrences
for select to authenticated
using (
  exists (
    select 1 from comunhao.events e
    where e.id = event_occurrences.event_id
      and (e.is_public or comunhao.is_church_member(e.church_id, auth.uid()))
  )
);
drop policy if exists comunhao_event_occurrences_manage_leader on comunhao.event_occurrences;
create policy comunhao_event_occurrences_manage_leader on comunhao.event_occurrences
for all to authenticated
using (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','event_manager']))
with check (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','event_manager']));
drop policy if exists comunhao_event_registrations_select_self_or_leader on comunhao.event_registrations;
create policy comunhao_event_registrations_select_self_or_leader on comunhao.event_registrations
for select to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from comunhao.events e
    where e.id = event_registrations.event_id
      and comunhao.has_church_role(e.church_id, auth.uid(), array['pastor','church_admin','organization_admin','event_manager'])
  )
);
drop policy if exists comunhao_event_registrations_insert_self on comunhao.event_registrations;
create policy comunhao_event_registrations_insert_self on comunhao.event_registrations
for insert to authenticated
with check (user_id = auth.uid());
drop policy if exists comunhao_event_registrations_update_self_or_leader on comunhao.event_registrations;
create policy comunhao_event_registrations_update_self_or_leader on comunhao.event_registrations
for update to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from comunhao.events e
    where e.id = event_registrations.event_id
      and comunhao.has_church_role(e.church_id, auth.uid(), array['pastor','church_admin','organization_admin','event_manager'])
  )
);
grant select, insert, update, delete on
  comunhao.ministries,
  comunhao.ministry_members,
  comunhao.groups,
  comunhao.group_members,
  comunhao.events,
  comunhao.event_occurrences,
  comunhao.event_registrations,
  comunhao.announcements,
  comunhao.communications
to authenticated;
grant all privileges on
  comunhao.ministries,
  comunhao.ministry_members,
  comunhao.groups,
  comunhao.group_members,
  comunhao.events,
  comunhao.event_occurrences,
  comunhao.event_registrations,
  comunhao.announcements,
  comunhao.communications
to service_role;
commit;
