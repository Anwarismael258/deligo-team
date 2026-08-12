begin;
create table if not exists core.hq_integration_credentials (
  integration_key text primary key,
  secret_sha256 text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  rotated_at timestamptz not null default now()
);
alter table core.hq_integration_credentials enable row level security;
revoke all on core.hq_integration_credentials from public, anon, authenticated;
create or replace function public.hq_dashboard_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, core, deligo, comunhao, sarca, taomoz
as $$
declare
  supplied_secret text;
  expected_hash text;
begin
  supplied_secret := coalesce(
    (current_setting('request.headers', true)::jsonb ->> 'x-hq-integration-secret'),
    ''
  );

  select secret_sha256 into expected_hash
  from core.hq_integration_credentials
  where integration_key = 'deligo-triunfal-hq' and active;

  if expected_hash is null
     or encode(extensions.digest(supplied_secret, 'sha256'), 'hex') <> expected_hash then
    raise insufficient_privilege using message = 'HQ integration authentication failed';
  end if;

  return jsonb_build_object(
    'environment', 'Deligo-Platform-Staging',
    'checkedAt', to_char(clock_timestamp() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'platforms', jsonb_build_array(
      jsonb_build_object(
        'slug', 'deligo', 'name', 'DeliGo', 'connected', true,
        'metrics', jsonb_build_array(
          jsonb_build_object('key','users','label','Utilizadores','value',(select count(*) from deligo.legacy_profiles)),
          jsonb_build_object('key','orders','label','Pedidos','value',(select count(*) from deligo.legacy_orders)),
          jsonb_build_object('key','restaurants','label','Restaurantes','value',(select count(*) from deligo.legacy_restaurants)),
          jsonb_build_object('key','couriers','label','Estafetas','value',(select count(*) from deligo.legacy_couriers))
        )
      ),
      jsonb_build_object(
        'slug', 'comunhao', 'name', 'Comunhão', 'connected', true,
        'metrics', jsonb_build_array(
          jsonb_build_object('key','members','label','Membros','value',(select count(*) from comunhao.profiles)),
          jsonb_build_object('key','churches','label','Igrejas','value',(select count(*) from comunhao.churches)),
          jsonb_build_object('key','events','label','Eventos','value',(select count(*) from comunhao.events)),
          jsonb_build_object('key','donations','label','Doações','value',(select count(*) from comunhao.donations))
        )
      ),
      jsonb_build_object(
        'slug', 'taomoz', 'name', 'TaoMoz', 'connected', true,
        'metrics', jsonb_build_array(
          jsonb_build_object('key','buyers','label','Compradores','value',(select count(*) from taomoz.buyer_profiles)),
          jsonb_build_object('key','sellers','label','Vendedores','value',(select count(*) from taomoz.seller_profiles)),
          jsonb_build_object('key','products','label','Produtos','value',(select count(*) from taomoz.products)),
          jsonb_build_object('key','orders','label','Pedidos','value',(select count(*) from taomoz.orders))
        )
      ),
      jsonb_build_object(
        'slug', 'sarca', 'name', 'SARCA', 'connected', true,
        'metrics', jsonb_build_array(
          jsonb_build_object('key','passengers','label','Passageiros','value',(select count(*) from sarca.passenger_profiles)),
          jsonb_build_object('key','drivers','label','Motoristas','value',(select count(*) from sarca.driver_profiles)),
          jsonb_build_object('key','vehicles','label','Viaturas','value',(select count(*) from sarca.vehicles)),
          jsonb_build_object('key','trips','label','Viagens','value',(select count(*) from sarca.trips))
        )
      )
    ),
    'operations', jsonb_build_object(
      'supportCases', (select count(*) from core.support_cases),
      'campaigns', (select count(*) from core.marketing_campaigns),
      'fieldVisits', (select count(*) from core.field_visits),
      'auditEvents', (select count(*) from core.audit_logs)
    )
  );
end;
$$;
revoke all on function public.hq_dashboard_v1() from public;
grant execute on function public.hq_dashboard_v1() to anon, authenticated, service_role;
comment on function public.hq_dashboard_v1() is
  'Read-only aggregate surface for the DeliGo Triunfal HQ. Requires the server-only integration secret header.';
commit;
