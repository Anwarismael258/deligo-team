begin;
alter table sarca.vehicles
  add column if not exists service_class text,
  add column if not exists has_air_conditioning boolean not null default false,
  add column if not exists photo_url text;
update sarca.vehicles
set service_class = 'economico'
where service_class is null;
alter table sarca.vehicles
  alter column service_class set default 'economico',
  alter column service_class set not null;
alter table sarca.vehicles
  drop constraint if exists sarca_vehicles_service_class_check;
alter table sarca.vehicles
  add constraint sarca_vehicles_service_class_check
  check (service_class in ('economico', 'conforto', 'moto', 'txopela'));
alter table sarca.trips
  add column if not exists service_class text,
  add column if not exists service_label text;
update sarca.trips
set service_class = coalesce(service_class, 'economico'),
    service_label = coalesce(service_label, 'Económico')
where service_class is null or service_label is null;
alter table sarca.trips
  alter column service_class set default 'economico',
  alter column service_class set not null;
alter table sarca.trips
  drop constraint if exists sarca_trips_service_class_check;
alter table sarca.trips
  add constraint sarca_trips_service_class_check
  check (service_class in ('economico', 'conforto', 'moto', 'txopela'));
create index if not exists idx_sarca_trips_matching
  on sarca.trips (status, service_class, requested_at)
  where driver_user_id is null;
drop policy if exists sarca_trips_read_available_driver on sarca.trips;
create policy sarca_trips_read_available_driver
on sarca.trips
for select
to authenticated
using (
  status = 'searching_driver'
  and driver_user_id is null
  and exists (
    select 1
    from sarca.driver_profiles dp
    where dp.user_id = auth.uid()
      and dp.status = 'active'
      and dp.onboarding_completed
      and dp.is_online
  )
);
create or replace function sarca.accept_trip_atomic(
  p_trip_id uuid,
  p_vehicle_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_vehicle sarca.vehicles%rowtype;
  v_trip sarca.trips%rowtype;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from sarca.driver_profiles dp
    where dp.user_id = v_user_id
      and dp.status = 'active'
      and dp.onboarding_completed
      and dp.is_online
  ) then
    raise exception 'driver_not_eligible' using errcode = '42501';
  end if;

  select *
  into v_vehicle
  from sarca.vehicles v
  where v.id = p_vehicle_id
    and v.driver_user_id = v_user_id
    and v.status = 'active';

  if not found then
    raise exception 'active_vehicle_required' using errcode = '42501';
  end if;

  update sarca.trips
  set driver_user_id = v_user_id,
      vehicle_id = v_vehicle.id,
      status = 'driver_assigned',
      accepted_at = now(),
      updated_at = now()
  where id = p_trip_id
    and status = 'searching_driver'
    and driver_user_id is null
    and service_class = v_vehicle.service_class
  returning * into v_trip;

  if not found then
    select *
    into v_trip
    from sarca.trips t
    where t.id = p_trip_id
      and t.driver_user_id = v_user_id
      and t.vehicle_id = v_vehicle.id
      and t.status = 'driver_assigned';

    if found then
      return jsonb_build_object('replayed', true, 'trip', to_jsonb(v_trip));
    end if;

    raise exception 'trip_not_available' using errcode = '40001';
  end if;

  insert into sarca.trip_events (
    trip_id,
    actor_user_id,
    event_type,
    payload
  )
  values (
    v_trip.id,
    v_user_id,
    'driver_assigned',
    jsonb_build_object(
      'vehicle_id', v_vehicle.id,
      'service_class', v_vehicle.service_class
    )
  );

  return jsonb_build_object('replayed', false, 'trip', to_jsonb(v_trip));
end;
$$;

create or replace function sarca.progress_driver_trip(
  p_trip_id uuid,
  p_expected_status text,
  p_next_status text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_trip sarca.trips%rowtype;
  v_event_type text;
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '28000';
  end if;

  if (p_expected_status, p_next_status) not in (
    ('driver_assigned', 'driver_arriving'),
    ('driver_arriving', 'in_progress'),
    ('in_progress', 'payment_pending')
  ) then
    raise exception 'driver_transition_not_allowed' using errcode = '42501';
  end if;

  v_event_type := case p_next_status
    when 'driver_arriving' then 'driver_arriving'
    when 'in_progress' then 'trip_started'
    when 'payment_pending' then 'trip_payment_pending'
  end;

  update sarca.trips
  set status = p_next_status,
      started_at = case
        when p_next_status = 'in_progress' then coalesce(started_at, now())
        else started_at
      end,
      updated_at = now()
  where id = p_trip_id
    and driver_user_id = v_user_id
    and status = p_expected_status
  returning * into v_trip;

  if not found then
    select *
    into v_trip
    from sarca.trips t
    where t.id = p_trip_id
      and t.driver_user_id = v_user_id
      and t.status = p_next_status;

    if found then
      return jsonb_build_object('replayed', true, 'trip', to_jsonb(v_trip));
    end if;

    raise exception 'trip_state_conflict' using errcode = '40001';
  end if;

  insert into sarca.trip_events (
    trip_id,
    actor_user_id,
    event_type,
    payload
  )
  values (
    v_trip.id,
    v_user_id,
    v_event_type,
    jsonb_build_object(
      'previous_status', p_expected_status,
      'next_status', p_next_status
    )
  );

  return jsonb_build_object('replayed', false, 'trip', to_jsonb(v_trip));
end;
$$;

revoke all on function sarca.accept_trip_atomic(uuid, uuid) from public;
revoke all on function sarca.progress_driver_trip(uuid, text, text) from public;
grant execute on function sarca.accept_trip_atomic(uuid, uuid) to authenticated;
grant execute on function sarca.progress_driver_trip(uuid, text, text) to authenticated;

commit;;
