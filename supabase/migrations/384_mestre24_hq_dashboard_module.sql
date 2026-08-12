begin;

-- Read-only Mestre24 aggregate for the existing HQ dashboard. It uses the
-- same server-only integration secret as the other corporate aggregates.
create or replace function public.hq_mestre24_module_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, core, mestre24
as $$
declare
  supplied_secret text;
  expected_hash text;
  professional_count bigint;
  client_count bigint;
  request_count bigint;
  active_subscriptions bigint;
  confirmed_revenue numeric;
  people jsonb;
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

  select count(*) into professional_count from mestre24.professional_profiles;
  select count(*) into client_count from mestre24.profiles where account_type = 'client';
  select count(*) into request_count from mestre24.service_requests;
  select count(*) into active_subscriptions from mestre24.subscription_cycles
    where status = 'active' and expires_at > now();
  select coalesce(sum(amount), 0) into confirmed_revenue from mestre24.subscription_cycles
    where status in ('paid', 'active') and paid_at is not null;
  select coalesce(jsonb_agg(person order by created_at desc), '[]'::jsonb) into people
  from (
    select p.user_id::text as id, p.full_name as name, p.account_type as role, p.created_at
    from mestre24.profiles p order by p.created_at desc limit 10
  ) person;

  return jsonb_build_object(
    'platform', jsonb_build_object(
      'slug', 'mestre24', 'name', 'Mestre24', 'connected', true,
      'metrics', jsonb_build_array(
        jsonb_build_object('key', 'professionals', 'label', 'Profissionais', 'value', professional_count),
        jsonb_build_object('key', 'clients', 'label', 'Clientes', 'value', client_count),
        jsonb_build_object('key', 'requests', 'label', 'Pedidos de serviço', 'value', request_count),
        jsonb_build_object('key', 'subscriptions', 'label', 'Subscrições ativas', 'value', active_subscriptions)
      )
    ),
    'module', jsonb_build_object(
      'slug', 'mestre24', 'name', 'Mestre24', 'value', confirmed_revenue, 'people', people
    )
  );
end;
$$;
revoke all on function public.hq_mestre24_module_v1() from public;
grant execute on function public.hq_mestre24_module_v1() to anon, authenticated, service_role;

commit;
