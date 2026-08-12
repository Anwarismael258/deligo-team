begin;
create table if not exists sarca.passenger_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  emergency_contact_phone text,
  default_payment_method text not null default 'cash'
    check (default_payment_method in ('cash', 'mpesa', 'emola', 'mkesh', 'wallet')),
  rating numeric(3,2),
  total_trips integer not null default 0 check (total_trips >= 0),
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists sarca.driver_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'suspended', 'rejected')),
  commission_rate_bps integer not null default 600
    check (commission_rate_bps between 0 and 10000),
  licence_number text,
  onboarding_completed boolean not null default false,
  is_online boolean not null default false,
  current_lat numeric(9,6),
  current_lng numeric(9,6),
  rating numeric(3,2),
  total_trips integer not null default 0 check (total_trips >= 0),
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists sarca.vehicles (
  id uuid primary key,
  driver_user_id uuid not null references sarca.driver_profiles(user_id) on delete cascade,
  make text,
  model text,
  color text,
  plate_number text not null unique,
  year smallint,
  status text not null default 'active'
    check (status in ('active', 'inactive', 'suspended', 'archived')),
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists sarca.driver_documents (
  id uuid primary key,
  driver_user_id uuid not null references sarca.driver_profiles(user_id) on delete cascade,
  document_type text not null,
  storage_path text not null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'expired')),
  reviewed_by_user_id uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  rejection_reason text,
  expires_at date,
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists sarca.pricing_rules (
  id uuid primary key,
  name text not null,
  city text not null default 'Maputo',
  base_fare_minor bigint not null default 0 check (base_fare_minor >= 0),
  per_km_minor bigint not null default 0 check (per_km_minor >= 0),
  per_minute_minor bigint not null default 0 check (per_minute_minor >= 0),
  minimum_fare_minor bigint not null default 0 check (minimum_fare_minor >= 0),
  cancellation_fee_minor bigint not null default 0 check (cancellation_fee_minor >= 0),
  surge_multiplier numeric(6,2) not null default 1 check (surge_multiplier >= 1),
  is_active boolean not null default true,
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists sarca.trips (
  id uuid primary key,
  passenger_user_id uuid not null references sarca.passenger_profiles(user_id) on delete restrict,
  driver_user_id uuid references sarca.driver_profiles(user_id) on delete set null,
  vehicle_id uuid references sarca.vehicles(id) on delete set null,
  pricing_rule_id uuid references sarca.pricing_rules(id) on delete set null,
  payment_transaction_id uuid references payments.payment_transactions(id) on delete set null,
  status text not null default 'draft'
    check (status in (
      'draft', 'searching_driver', 'driver_assigned', 'driver_arriving',
      'in_progress', 'completed', 'cancelled_by_rider', 'cancelled_by_driver',
      'expired', 'payment_pending', 'payment_failed', 'refunded'
    )),
  payment_method text not null default 'cash'
    check (payment_method in ('cash', 'mpesa', 'emola', 'mkesh', 'wallet')),
  payment_status text not null default 'created',
  funds_status text not null default 'none'
    check (funds_status in ('none', 'held_in_escrow', 'released', 'partially_refunded', 'refunded')),
  currency_code char(3) not null default 'MZN',
  pickup_address text,
  dropoff_address text,
  pickup_lat numeric(9,6),
  pickup_lng numeric(9,6),
  dropoff_lat numeric(9,6),
  dropoff_lng numeric(9,6),
  distance_meters integer check (distance_meters is null or distance_meters >= 0),
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  estimated_fare_minor bigint check (estimated_fare_minor is null or estimated_fare_minor >= 0),
  final_fare_minor bigint check (final_fare_minor is null or final_fare_minor >= 0),
  commission_minor bigint check (commission_minor is null or commission_minor >= 0),
  driver_net_minor bigint check (driver_net_minor is null or driver_net_minor >= 0),
  cancellation_reason text,
  migration_batch text,
  requested_at timestamptz not null default now(),
  accepted_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists sarca.trip_events (
  id bigint generated always as identity primary key,
  trip_id uuid not null references sarca.trips(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  legacy_event_id bigint,
  migration_batch text,
  created_at timestamptz not null default now()
);
create unique index if not exists idx_sarca_trip_events_legacy
  on sarca.trip_events (legacy_event_id)
  where legacy_event_id is not null;
create index if not exists idx_sarca_driver_status_online on sarca.driver_profiles (status, is_online);
create index if not exists idx_sarca_vehicles_driver on sarca.vehicles (driver_user_id, status);
create index if not exists idx_sarca_trips_passenger on sarca.trips (passenger_user_id, requested_at desc);
create index if not exists idx_sarca_trips_driver on sarca.trips (driver_user_id, requested_at desc);
create index if not exists idx_sarca_trips_status on sarca.trips (status, requested_at);
create index if not exists idx_sarca_trip_events_trip on sarca.trip_events (trip_id, created_at);
create table if not exists sarca.trip_status_transitions (
  from_status text not null,
  to_status text not null,
  primary key (from_status, to_status)
);
insert into sarca.trip_status_transitions (from_status, to_status)
values
  ('draft', 'searching_driver'),
  ('searching_driver', 'driver_assigned'),
  ('searching_driver', 'expired'),
  ('searching_driver', 'cancelled_by_rider'),
  ('driver_assigned', 'driver_arriving'),
  ('driver_assigned', 'cancelled_by_rider'),
  ('driver_assigned', 'cancelled_by_driver'),
  ('driver_arriving', 'in_progress'),
  ('driver_arriving', 'cancelled_by_rider'),
  ('driver_arriving', 'cancelled_by_driver'),
  ('in_progress', 'completed'),
  ('in_progress', 'payment_pending'),
  ('payment_pending', 'completed'),
  ('payment_pending', 'payment_failed'),
  ('completed', 'refunded'),
  ('payment_failed', 'cancelled_by_rider')
on conflict do nothing;
create or replace function sarca.is_valid_trip_transition(p_from text, p_to text)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from sarca.trip_status_transitions
    where from_status = p_from and to_status = p_to
  );
$$;
create or replace function sarca.prevent_trip_event_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'sarca.trip_events is append-only; create a compensating event';
end;
$$;
drop trigger if exists trg_sarca_trip_events_no_update on sarca.trip_events;
create trigger trg_sarca_trip_events_no_update
before update on sarca.trip_events
for each row execute function sarca.prevent_trip_event_mutation();
drop trigger if exists trg_sarca_trip_events_no_delete on sarca.trip_events;
create trigger trg_sarca_trip_events_no_delete
before delete on sarca.trip_events
for each row execute function sarca.prevent_trip_event_mutation();
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'passenger_profiles', 'driver_profiles', 'vehicles', 'driver_documents',
    'pricing_rules', 'trips'
  ]
  loop
    execute format('drop trigger if exists %I on sarca.%I', 'trg_sarca_' || v_table || '_touch_updated_at', v_table);
    execute format(
      'create trigger %I before update on sarca.%I for each row execute function public.touch_updated_at()',
      'trg_sarca_' || v_table || '_touch_updated_at', v_table
    );
    execute format('alter table sarca.%I enable row level security', v_table);
  end loop;
  alter table sarca.trip_events enable row level security;
  alter table sarca.trip_status_transitions enable row level security;
end;
$$;
drop policy if exists sarca_passenger_profiles_self on sarca.passenger_profiles;
create policy sarca_passenger_profiles_self on sarca.passenger_profiles
for all to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()))
with check (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists sarca_driver_profiles_select_self_or_admin on sarca.driver_profiles;
create policy sarca_driver_profiles_select_self_or_admin on sarca.driver_profiles
for select to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists sarca_driver_profiles_update_self_or_admin on sarca.driver_profiles;
create policy sarca_driver_profiles_update_self_or_admin on sarca.driver_profiles
for update to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()))
with check (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists sarca_vehicles_select_driver_or_trip_party on sarca.vehicles;
create policy sarca_vehicles_select_driver_or_trip_party on sarca.vehicles
for select to authenticated
using (
  driver_user_id = auth.uid()
  or core.is_platform_admin(auth.uid())
  or exists (
    select 1 from sarca.trips t
    where t.vehicle_id = vehicles.id and t.passenger_user_id = auth.uid()
  )
);
drop policy if exists sarca_vehicles_manage_driver on sarca.vehicles;
create policy sarca_vehicles_manage_driver on sarca.vehicles
for all to authenticated
using (driver_user_id = auth.uid() or core.is_platform_admin(auth.uid()))
with check (driver_user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists sarca_driver_documents_self_or_admin on sarca.driver_documents;
create policy sarca_driver_documents_self_or_admin on sarca.driver_documents
for all to authenticated
using (driver_user_id = auth.uid() or core.is_platform_admin(auth.uid()))
with check (driver_user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists sarca_pricing_rules_read on sarca.pricing_rules;
create policy sarca_pricing_rules_read on sarca.pricing_rules
for select to authenticated using (is_active or core.is_platform_admin(auth.uid()));
drop policy if exists sarca_trips_read_party on sarca.trips;
create policy sarca_trips_read_party on sarca.trips
for select to authenticated
using (
  passenger_user_id = auth.uid()
  or driver_user_id = auth.uid()
  or core.is_platform_admin(auth.uid())
);
drop policy if exists sarca_trips_create_passenger on sarca.trips;
create policy sarca_trips_create_passenger on sarca.trips
for insert to authenticated
with check (passenger_user_id = auth.uid());
drop policy if exists sarca_trips_update_party on sarca.trips;
create policy sarca_trips_update_party on sarca.trips
for update to authenticated
using (
  passenger_user_id = auth.uid()
  or driver_user_id = auth.uid()
  or core.is_platform_admin(auth.uid())
);
drop policy if exists sarca_trip_events_read_party on sarca.trip_events;
create policy sarca_trip_events_read_party on sarca.trip_events
for select to authenticated
using (
  exists (
    select 1 from sarca.trips t
    where t.id = trip_events.trip_id
      and (
        t.passenger_user_id = auth.uid()
        or t.driver_user_id = auth.uid()
        or core.is_platform_admin(auth.uid())
      )
  )
);
drop policy if exists sarca_trip_events_insert_party on sarca.trip_events;
create policy sarca_trip_events_insert_party on sarca.trip_events
for insert to authenticated
with check (
  actor_user_id = auth.uid()
  and exists (
    select 1 from sarca.trips t
    where t.id = trip_events.trip_id
      and (t.passenger_user_id = auth.uid() or t.driver_user_id = auth.uid())
  )
);
drop policy if exists sarca_trip_transitions_read on sarca.trip_status_transitions;
create policy sarca_trip_transitions_read on sarca.trip_status_transitions
for select to authenticated using (true);
grant select, insert, update, delete on
  sarca.passenger_profiles, sarca.driver_profiles, sarca.vehicles,
  sarca.driver_documents, sarca.pricing_rules, sarca.trips
to authenticated;
grant select, insert on sarca.trip_events to authenticated;
grant select on sarca.trip_status_transitions to authenticated;
grant all privileges on all tables in schema sarca to service_role;
grant usage, select on all sequences in schema sarca to authenticated, service_role;
grant execute on function sarca.is_valid_trip_transition(text, text) to authenticated, service_role;
commit;
