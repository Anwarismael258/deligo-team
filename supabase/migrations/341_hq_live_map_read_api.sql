begin;

create or replace function public.hq_live_map_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, core, sarca, taomoz
as $$
declare
  supplied_secret text;
  expected_hash text;
begin
  supplied_secret := coalesce((current_setting('request.headers', true)::jsonb ->> 'x-hq-integration-secret'), '');
  select secret_sha256 into expected_hash
  from core.hq_integration_credentials
  where integration_key = 'deligo-triunfal-hq' and active;

  if expected_hash is null or encode(extensions.digest(supplied_secret, 'sha256'), 'hex') <> expected_hash then
    raise insufficient_privilege using message = 'HQ integration authentication failed';
  end if;

  return jsonb_build_object(
    'checkedAt', to_char(clock_timestamp() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'markers', coalesce((
      select jsonb_agg(marker order by marker->>'platform', marker->>'updatedAt' desc)
      from (
        select jsonb_build_object(
          'id', 'deligo:' || d.id::text,
          'platform', 'DeliGo',
          'role', 'Estafeta',
          'latitude', d.current_latitude,
          'longitude', d.current_longitude,
          'updatedAt', d.location_recorded_at
        ) marker
        from public.deliveries d
        where d.current_latitude is not null
          and d.current_longitude is not null
          and d.location_recorded_at > now() - interval '5 minutes'
          and coalesce(d.status::text, '') not in ('delivered', 'cancelled', 'failed')

        union all

        select jsonb_build_object(
          'id', 'sarca:' || dp.user_id::text,
          'platform', 'SARCA',
          'role', 'Motorista',
          'latitude', dp.current_lat,
          'longitude', dp.current_lng,
          'updatedAt', dp.updated_at
        ) marker
        from sarca.driver_profiles dp
        where dp.status = 'active'
          and dp.is_online
          and dp.current_lat is not null
          and dp.current_lng is not null
          and dp.updated_at > now() - interval '5 minutes'

        union all

        select jsonb_build_object(
          'id', 'taomoz:' || cp.courier_id::text,
          'platform', 'TaoMoz',
          'role', 'Courier',
          'latitude', cp.latitude,
          'longitude', cp.longitude,
          'updatedAt', cp.last_seen_at
        ) marker
        from taomoz.courier_presence cp
        where cp.is_online
          and cp.latitude is not null
          and cp.longitude is not null
          and cp.last_seen_at > now() - interval '5 minutes'
      ) markers
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.hq_live_map_v1() from public;
grant execute on function public.hq_live_map_v1() to anon, authenticated, service_role;
comment on function public.hq_live_map_v1() is
  'Private HQ-only live location feed. It returns only fresh positions and requires the server integration secret.';

commit;
