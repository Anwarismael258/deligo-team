begin;

create table if not exists core.hq_location_authorizations (
  platform text not null check (platform in ('deligo','sarca','taomoz')),
  worker_id uuid not null,
  authorized boolean not null default false,
  granted_at timestamptz,
  revoked_at timestamptz,
  expires_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (platform, worker_id),
  check ((authorized and revoked_at is null) or not authorized)
);
alter table core.hq_location_authorizations enable row level security;
revoke all on core.hq_location_authorizations from public, anon, authenticated;
grant all on core.hq_location_authorizations to service_role;

create or replace function public.hq_live_map_v1()
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, core, sarca, taomoz
as $$
declare supplied_secret text; expected_hash text;
begin
  supplied_secret := coalesce((current_setting('request.headers', true)::jsonb ->> 'x-hq-integration-secret'), '');
  select secret_sha256 into expected_hash from core.hq_integration_credentials where integration_key = 'deligo-triunfal-hq' and active;
  if expected_hash is null or encode(extensions.digest(supplied_secret, 'sha256'), 'hex') <> expected_hash then raise insufficient_privilege using message = 'HQ integration authentication failed'; end if;
  return jsonb_build_object('checkedAt', to_char(clock_timestamp() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'), 'markers', coalesce((
    select jsonb_agg(marker order by marker->>'platform', marker->>'updatedAt' desc) from (
      select jsonb_build_object('id','deligo:'||d.courier_id::text,'workerId',d.courier_id,'platform','DeliGo','role','Estafeta','workerName',coalesce(nullif(p.full_name,''),nullif(p.display_name,''),'Estafeta DeliGo'),'status',case when d.status::text in ('in_transit','picked_up') then 'em_servico' else 'ocupado' end,'service',coalesce(d.order_id::text,''),'latitude',d.current_latitude,'longitude',d.current_longitude,'updatedAt',d.location_recorded_at) marker
      from public.deliveries d left join core.profiles p on p.user_id=d.courier_id join core.hq_location_authorizations a on a.platform='deligo' and a.worker_id=d.courier_id and a.authorized and (a.expires_at is null or a.expires_at>now())
      where d.current_latitude is not null and d.current_longitude is not null and d.location_recorded_at>now()-interval '5 minutes' and coalesce(d.status::text,'') not in ('delivered','cancelled','failed')
      union all
      select jsonb_build_object('id','sarca:'||dp.user_id::text,'workerId',dp.user_id,'platform','SARCA','role','Motorista','workerName',coalesce(nullif(p.full_name,''),nullif(p.display_name,''),'Motorista SARCA'),'status',case when dp.is_online then 'disponivel' else 'offline' end,'service','','latitude',dp.current_lat,'longitude',dp.current_lng,'updatedAt',dp.updated_at) marker
      from sarca.driver_profiles dp left join core.profiles p on p.user_id=dp.user_id join core.hq_location_authorizations a on a.platform='sarca' and a.worker_id=dp.user_id and a.authorized and (a.expires_at is null or a.expires_at>now())
      where dp.status='active' and dp.is_online and dp.current_lat is not null and dp.current_lng is not null and dp.updated_at>now()-interval '5 minutes'
      union all
      select jsonb_build_object('id','taomoz:'||cp.courier_id::text,'workerId',cp.courier_id,'platform','TaoMoz','role','Entregador','workerName',coalesce(nullif(p.full_name,''),nullif(p.display_name,''),'Entregador TaoMoz'),'status',case when c.is_available then 'disponivel' else 'ocupado' end,'service','','latitude',cp.latitude,'longitude',cp.longitude,'updatedAt',cp.last_seen_at) marker
      from taomoz.courier_presence cp join taomoz.courier_profiles c on c.id=cp.courier_id left join core.profiles p on p.user_id=c.user_id join core.hq_location_authorizations a on a.platform='taomoz' and a.worker_id=cp.courier_id and a.authorized and (a.expires_at is null or a.expires_at>now())
      where cp.is_online and cp.latitude is not null and cp.longitude is not null and cp.last_seen_at>now()-interval '5 minutes'
    ) markers), '[]'::jsonb));
end; $$;
revoke all on function public.hq_live_map_v1() from public;
grant execute on function public.hq_live_map_v1() to anon, authenticated, service_role;
commit;
