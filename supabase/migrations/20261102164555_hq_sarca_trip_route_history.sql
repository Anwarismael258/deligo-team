begin;

-- Verified SARCA telemetry retained by HQ for trip history and replay.
-- Points are never synthesised from origin/destination coordinates.
create table if not exists hq.sarca_trip_route_points (
  id bigint generated always as identity primary key,
  trip_id uuid not null references sarca.trips(id) on delete cascade,
  source text not null check (source in ('driver', 'rider', 'system')),
  actor_user_id uuid references auth.users(id) on delete set null,
  recorded_at timestamptz not null,
  latitude numeric(9,6) not null check (latitude between -90 and 90),
  longitude numeric(9,6) not null check (longitude between -180 and 180),
  accuracy_meters numeric(8,2) check (accuracy_meters is null or accuracy_meters >= 0),
  sequence_no integer check (sequence_no is null or sequence_no >= 0),
  is_offline_sync boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (trip_id, source, recorded_at, latitude, longitude)
);

create index if not exists idx_hq_sarca_route_points_trip_time
  on hq.sarca_trip_route_points (trip_id, recorded_at asc);
create index if not exists idx_hq_sarca_route_points_source_time
  on hq.sarca_trip_route_points (source, recorded_at desc);

alter table hq.sarca_trip_route_points enable row level security;
revoke all on hq.sarca_trip_route_points from public, anon, authenticated;
grant all on hq.sarca_trip_route_points to service_role;
grant usage, select on sequence hq.sarca_trip_route_points_id_seq to service_role;

-- Server-to-server ingestion. The SARCA application calls this through the
-- trusted HQ integration, so client roles never receive direct table access.
create or replace function hq.record_sarca_trip_route_points(
  p_trip_id uuid,
  p_source text,
  p_points jsonb
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, hq, sarca
as $$
declare
  inserted_count integer := 0;
  item jsonb;
  lat numeric;
  lng numeric;
  at timestamptz;
begin
  if p_source not in ('driver', 'rider', 'system') then
    raise exception 'invalid_route_point_source' using errcode = '22023';
  end if;
  if not exists (select 1 from sarca.trips where id = p_trip_id) then
    raise exception 'sarca_trip_not_found' using errcode = 'P0002';
  end if;
  if jsonb_typeof(coalesce(p_points, '[]'::jsonb)) <> 'array' then
    raise exception 'route_points_must_be_array' using errcode = '22023';
  end if;

  for item in select value from jsonb_array_elements(p_points)
  loop
    lat := nullif(item->>'latitude', '')::numeric;
    lng := nullif(item->>'longitude', '')::numeric;
    at := nullif(item->>'recorded_at', '')::timestamptz;
    if lat is null or lng is null or at is null
       or lat < -90 or lat > 90 or lng < -180 or lng > 180 then
      continue;
    end if;
    insert into hq.sarca_trip_route_points (
      trip_id, source, actor_user_id, recorded_at, latitude, longitude,
      accuracy_meters, sequence_no, is_offline_sync, metadata
    ) values (
      p_trip_id,
      p_source,
      case when item->>'actor_user_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then (item->>'actor_user_id')::uuid end,
      at,
      lat,
      lng,
      case when item->>'accuracy_meters' ~ '^[0-9]+(\\.[0-9]+)?$' then (item->>'accuracy_meters')::numeric end,
      case when item->>'sequence_no' ~ '^[0-9]+$' then (item->>'sequence_no')::integer end,
      coalesce((item->>'is_offline_sync')::boolean, false),
      coalesce(item->'metadata', '{}'::jsonb)
    ) on conflict do nothing;
    if found then
      inserted_count := inserted_count + 1;
    end if;
  end loop;
  return inserted_count;
end;
$$;

revoke all on function hq.record_sarca_trip_route_points(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function hq.record_sarca_trip_route_points(uuid, text, jsonb) to service_role;

commit;
