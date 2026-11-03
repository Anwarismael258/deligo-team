begin;

-- Invited workers do not receive primary_role_id until their terms are accepted.
-- Keep the login context available for the terms gate by resolving the requested
-- role without granting operational access before activation.
create or replace function public.hq_actor_context_for_login_v1(
  p_auth_user_id uuid,
  p_phone_e164 text
) returns jsonb
language plpgsql
security definer
set search_path = hq, public, pg_temp
as $$
declare actor jsonb;
begin
  if p_auth_user_id is null or p_phone_e164 is null
     or p_phone_e164 !~ '^[+][0-9]{12}$' then
    return null;
  end if;

  select jsonb_build_object(
    'employee_id', e.id,
    'employee_code', e.employee_code,
    'name', e.display_name,
    'role', coalesce(primary_role.code, requested_role.code, e.requested_role_code),
    'status', e.status
  )
  into actor
  from hq.employees e
  left join hq.roles primary_role on primary_role.id = e.primary_role_id
  left join hq.roles requested_role on requested_role.code = e.requested_role_code and requested_role.active
  where (e.auth_user_id = p_auth_user_id or e.phone_e164 = p_phone_e164)
    and e.status in ('active', 'invited')
  order by (e.auth_user_id = p_auth_user_id) desc
  limit 1;

  return actor;
end;
$$;

revoke all on function public.hq_actor_context_for_login_v1(uuid, text) from public, anon;
grant execute on function public.hq_actor_context_for_login_v1(uuid, text) to service_role, authenticated;

notify pgrst, 'reload schema';
commit;
