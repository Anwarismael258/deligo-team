begin;

-- The HQ is a trusted server-side consumer.  Its service-role credential is
-- already stored only in the private runtime, so it may read the consolidated
-- dashboard without relying on a separately rotated header secret.  The
-- existing integration-secret flow remains valid for non-service callers.
create or replace function public.hq_dashboard_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, core, deligo, comunhao, sarca, taomoz
as $$
declare
  supplied_secret text;
  expected_hash text;
  trusted_service boolean;
begin
  supplied_secret := coalesce((current_setting('request.headers', true)::jsonb ->> 'x-hq-integration-secret'), '');
  trusted_service := coalesce(auth.role(), '') = 'service_role';
  select secret_sha256 into expected_hash from core.hq_integration_credentials
  where integration_key = 'deligo-triunfal-hq' and active;
  if not trusted_service and (expected_hash is null or encode(extensions.digest(supplied_secret, 'sha256'), 'hex') <> expected_hash) then
    raise insufficient_privilege using message = 'HQ integration authentication failed';
  end if;
  return (select public.hq_dashboard_v1_legacy_compatible());
end;
$$;

-- Preserve the exact existing aggregate definition while adding the trusted
-- server path.  The helper is created from the original function body below.
create or replace function public.hq_dashboard_v1_legacy_compatible()
returns jsonb language sql security definer
set search_path = pg_catalog, public, core, deligo, comunhao, sarca, taomoz
as $$
 select jsonb_build_object(
  'environment','Deligo-Platform-Staging','checkedAt',to_char(clock_timestamp() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'platforms',jsonb_build_array(
   jsonb_build_object('slug','deligo','name','DeliGo','connected',true,'metrics',jsonb_build_array(jsonb_build_object('key','users','label','Utilizadores','value',(select count(*) from deligo.legacy_profiles)),jsonb_build_object('key','orders','label','Pedidos','value',(select count(*) from deligo.legacy_orders)),jsonb_build_object('key','restaurants','label','Restaurantes','value',(select count(*) from deligo.legacy_restaurants)),jsonb_build_object('key','couriers','label','Estafetas','value',(select count(*) from deligo.legacy_couriers)))),
   jsonb_build_object('slug','comunhao','name','Comunhão','connected',true,'metrics',jsonb_build_array(jsonb_build_object('key','members','label','Membros','value',(select count(*) from comunhao.profiles)),jsonb_build_object('key','churches','label','Igrejas','value',(select count(*) from comunhao.churches)),jsonb_build_object('key','events','label','Eventos','value',(select count(*) from comunhao.events)),jsonb_build_object('key','donations','label','Doações','value',(select count(*) from comunhao.donations)))),
   jsonb_build_object('slug','taomoz','name','TaoMoz','connected',true,'metrics',jsonb_build_array(jsonb_build_object('key','buyers','label','Compradores','value',(select count(*) from taomoz.buyer_profiles)),jsonb_build_object('key','sellers','label','Vendedores','value',(select count(*) from taomoz.seller_profiles)),jsonb_build_object('key','products','label','Produtos','value',(select count(*) from taomoz.products)),jsonb_build_object('key','orders','label','Pedidos','value',(select count(*) from taomoz.orders)))),
   jsonb_build_object('slug','sarca','name','SARCA','connected',true,'metrics',jsonb_build_array(jsonb_build_object('key','passengers','label','Passageiros','value',(select count(*) from sarca.passenger_profiles)),jsonb_build_object('key','drivers','label','Motoristas','value',(select count(*) from sarca.driver_profiles)),jsonb_build_object('key','vehicles','label','Viaturas','value',(select count(*) from sarca.vehicles)),jsonb_build_object('key','trips','label','Viagens','value',(select count(*) from sarca.trips))))),
  'operations',jsonb_build_object('supportCases',(select count(*) from core.support_cases),'campaigns',(select count(*) from core.marketing_campaigns),'fieldVisits',(select count(*) from core.field_visits),'auditEvents',(select count(*) from core.audit_logs))
 );
$$;

create or replace function public.hq_platform_modules_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, core, deligo, comunhao, sarca, taomoz
as $$
declare supplied_secret text; expected_hash text; trusted_service boolean;
begin
 supplied_secret := coalesce((current_setting('request.headers', true)::jsonb ->> 'x-hq-integration-secret'), '');
 trusted_service := coalesce(auth.role(), '') = 'service_role';
 select secret_sha256 into expected_hash from core.hq_integration_credentials where integration_key='deligo-triunfal-hq' and active;
 if not trusted_service and (expected_hash is null or encode(extensions.digest(supplied_secret,'sha256'),'hex') <> expected_hash) then raise insufficient_privilege using message='HQ integration authentication failed'; end if;
 return public.hq_platform_modules_v1_legacy_compatible();
end;
$$;

create or replace function public.hq_platform_modules_v1_legacy_compatible()
returns jsonb language sql security definer
set search_path = pg_catalog, public, core, deligo, comunhao, sarca, taomoz
as $$
 select jsonb_build_object('checkedAt',to_char(clock_timestamp() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),'currency','MZN',
 'totalValue',coalesce((select sum(coalesce(total_amount,total,0)) from deligo.legacy_orders),0)+coalesce((select sum(coalesce(amount,amount_minor::numeric/100,0)) from comunhao.donations),0)+coalesce((select sum(coalesce(final_fare_minor,0))::numeric/100 from sarca.trips),0)+coalesce((select sum(coalesce(grand_total_minor,0))::numeric/100 from taomoz.orders),0),
 'platforms',jsonb_build_array(
  jsonb_build_object('slug','deligo','name','DeliGo','value',coalesce((select sum(coalesce(total_amount,total,0)) from deligo.legacy_orders),0),'people',coalesce((select jsonb_agg(x order by x.created_at desc) from (select id::text,coalesce(nullif(full_name,''),'Utilizador DeliGo') name,coalesce(role,'cliente') role,created_at from deligo.legacy_profiles order by created_at desc limit 10)x),'[]'::jsonb)),
  jsonb_build_object('slug','comunhao','name','Comunhão','value',coalesce((select sum(coalesce(amount,amount_minor::numeric/100,0)) from comunhao.donations),0),'people',coalesce((select jsonb_agg(x order by x.created_at desc) from (select id::text,coalesce(nullif(full_name,''),'Membro Comunhão') name,'membro' role,created_at from comunhao.profiles order by created_at desc limit 10)x),'[]'::jsonb)),
  jsonb_build_object('slug','sarca','name','SARCA','value',coalesce((select sum(coalesce(final_fare_minor,0))::numeric/100 from sarca.trips),0),'people','[]'::jsonb),
  jsonb_build_object('slug','taomoz','name','TaoMoz','value',coalesce((select sum(coalesce(grand_total_minor,0))::numeric/100 from taomoz.orders),0),'people','[]'::jsonb)),
 'departments',jsonb_build_object('support',jsonb_build_object('total',(select count(*) from core.support_cases),'open',(select count(*) from core.support_cases where status not in ('resolved','closed'))),'marketing',jsonb_build_object('total',(select count(*) from core.marketing_campaigns),'active',(select count(*) from core.marketing_campaigns where status in ('review','approved','published'))),'field',jsonb_build_object('total',(select count(*) from core.field_visits),'active',(select count(*) from core.field_visits where status in ('planned','in_progress'))),'staff',jsonb_build_object('total',(select count(*) from core.staff_profiles),'active',(select count(*) from core.staff_profiles where employment_status='active'))));
$$;

revoke all on function public.hq_dashboard_v1_legacy_compatible() from public;
revoke all on function public.hq_platform_modules_v1_legacy_compatible() from public;
grant execute on function public.hq_dashboard_v1(), public.hq_platform_modules_v1() to anon, authenticated, service_role;

create or replace function public.hq_mestre24_module_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, core, mestre24
as $$
declare supplied_secret text; expected_hash text; trusted_service boolean; professional_count bigint; client_count bigint; request_count bigint; active_subscriptions bigint; confirmed_revenue numeric; people jsonb;
begin
 supplied_secret := coalesce((current_setting('request.headers',true)::jsonb ->> 'x-hq-integration-secret'),'');
 trusted_service := coalesce(auth.role(),'')='service_role';
 select secret_sha256 into expected_hash from core.hq_integration_credentials where integration_key='deligo-triunfal-hq' and active;
 if not trusted_service and (expected_hash is null or encode(extensions.digest(supplied_secret,'sha256'),'hex')<>expected_hash) then raise insufficient_privilege using message='HQ integration authentication failed'; end if;
 select count(*) into professional_count from mestre24.professional_profiles;
 select count(*) into client_count from mestre24.profiles where account_type='client';
 select count(*) into request_count from mestre24.service_requests;
 select count(*) into active_subscriptions from mestre24.subscription_cycles where status='active' and expires_at>now();
 select coalesce(sum(amount),0) into confirmed_revenue from mestre24.subscription_cycles where status in ('paid','active') and paid_at is not null;
 select coalesce(jsonb_agg(person order by created_at desc),'[]'::jsonb) into people from (select p.user_id::text id,p.full_name name,p.account_type role,p.created_at from mestre24.profiles p order by p.created_at desc limit 10) person;
 return jsonb_build_object('platform',jsonb_build_object('slug','mestre24','name','Mestre24','connected',true,'metrics',jsonb_build_array(jsonb_build_object('key','professionals','label','Profissionais','value',professional_count),jsonb_build_object('key','clients','label','Clientes','value',client_count),jsonb_build_object('key','requests','label','Pedidos de serviço','value',request_count),jsonb_build_object('key','subscriptions','label','Subscrições ativas','value',active_subscriptions))),'module',jsonb_build_object('slug','mestre24','name','Mestre24','value',confirmed_revenue,'people',people));
end;
$$;
grant execute on function public.hq_mestre24_module_v1() to anon, authenticated, service_role;
commit;
