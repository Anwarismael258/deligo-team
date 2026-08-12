begin;
create or replace function public.hq_platform_modules_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, core, deligo, comunhao, sarca, taomoz
as $$
declare
  supplied_secret text;
  expected_hash text;
begin
  supplied_secret := coalesce((current_setting('request.headers', true)::jsonb ->> 'x-hq-integration-secret'), '');
  select secret_sha256 into expected_hash from core.hq_integration_credentials
  where integration_key = 'deligo-triunfal-hq' and active;
  if expected_hash is null or encode(extensions.digest(supplied_secret, 'sha256'), 'hex') <> expected_hash then
    raise insufficient_privilege using message = 'HQ integration authentication failed';
  end if;

  return jsonb_build_object(
    'checkedAt', to_char(clock_timestamp() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'currency', 'MZN',
    'totalValue',
      coalesce((select sum(coalesce(total_amount,total,0)) from deligo.legacy_orders),0)
      + coalesce((select sum(coalesce(amount,amount_minor::numeric/100,0)) from comunhao.donations),0)
      + coalesce((select sum(coalesce(final_fare_minor,0))::numeric/100 from sarca.trips),0)
      + coalesce((select sum(coalesce(grand_total_minor,0))::numeric/100 from taomoz.orders),0),
    'platforms', jsonb_build_array(
      jsonb_build_object(
        'slug','deligo','name','DeliGo','value',coalesce((select sum(coalesce(total_amount,total,0)) from deligo.legacy_orders),0),
        'people',coalesce((select jsonb_agg(x order by x.created_at desc) from (select id::text,coalesce(nullif(full_name,''),'Utilizador DeliGo') name,coalesce(role,'cliente') role,created_at from deligo.legacy_profiles order by created_at desc limit 10) x),'[]'::jsonb)
      ),
      jsonb_build_object(
        'slug','comunhao','name','Comunhão','value',coalesce((select sum(coalesce(amount,amount_minor::numeric/100,0)) from comunhao.donations),0),
        'people',coalesce((select jsonb_agg(x order by x.created_at desc) from (select id::text,coalesce(nullif(full_name,''),'Membro Comunhão') name,'membro' role,created_at from comunhao.profiles order by created_at desc limit 10) x),'[]'::jsonb)
      ),
      jsonb_build_object(
        'slug','sarca','name','SARCA','value',coalesce((select sum(coalesce(final_fare_minor,0))::numeric/100 from sarca.trips),0),
        'people',coalesce((select jsonb_agg(x order by x.created_at desc) from (
          select p.user_id::text id,coalesce(nullif(cp.full_name,''),nullif(cp.display_name,''),'Utilizador SARCA') name,
            case when d.user_id is not null then 'motorista' else 'passageiro' end role,p.created_at
          from sarca.passenger_profiles p left join core.profiles cp on cp.user_id=p.user_id left join sarca.driver_profiles d on d.user_id=p.user_id
          order by p.created_at desc limit 10
        ) x),'[]'::jsonb)
      ),
      jsonb_build_object(
        'slug','taomoz','name','TaoMoz','value',coalesce((select sum(coalesce(grand_total_minor,0))::numeric/100 from taomoz.orders),0),
        'people',coalesce((select jsonb_agg(x order by x.created_at desc) from (
          select b.user_id::text id,coalesce(nullif(cp.full_name,''),nullif(cp.display_name,''),'Comprador TaoMoz') name,'comprador' role,b.created_at
          from taomoz.buyer_profiles b left join core.profiles cp on cp.user_id=b.user_id order by b.created_at desc limit 10
        ) x),'[]'::jsonb)
      )
    ),
    'departments', jsonb_build_object(
      'support', jsonb_build_object('total',(select count(*) from core.support_cases),'open',(select count(*) from core.support_cases where status not in ('resolved','closed'))),
      'marketing', jsonb_build_object('total',(select count(*) from core.marketing_campaigns),'active',(select count(*) from core.marketing_campaigns where status in ('review','approved','published'))),
      'field', jsonb_build_object('total',(select count(*) from core.field_visits),'active',(select count(*) from core.field_visits where status in ('planned','in_progress'))),
      'staff', jsonb_build_object('total',(select count(*) from core.staff_profiles),'active',(select count(*) from core.staff_profiles where employment_status='active'))
    )
  );
end;
$$;
revoke all on function public.hq_platform_modules_v1() from public;
grant execute on function public.hq_platform_modules_v1() to anon, authenticated, service_role;
comment on function public.hq_platform_modules_v1() is 'Server-only read API for HQ platform modules, people and processed-value aggregates.';
commit;
