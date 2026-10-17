begin;

-- Resolve phone-authenticated identities to one exact, active HQ employee.
-- Never auto-activate an employee or grant/alter a role.
create or replace function public.hq_actor_context_for_login_v1(
  p_auth_user_id uuid,
  p_phone_e164 text
) returns jsonb
language plpgsql
security definer
set search_path=hq,public,pg_temp
as $$
declare
  actor jsonb;
  matched_employee_id uuid;
  matched_auth_user_id uuid;
  matched_count integer;
begin
  if p_auth_user_id is null or p_phone_e164 is null
     or p_phone_e164 !~ '^\\+258[0-9]{9}$' then
    return null;
  end if;

  -- Existing identity links always take precedence, including suspended accounts.
  select jsonb_build_object(
    'employee_id',e.id,
    'employee_code',e.employee_code,
    'name',e.display_name,
    'role',r.code,
    'status',e.status
  )
  into actor
  from hq.employees e
  join hq.roles r on r.id=e.primary_role_id
  where e.auth_user_id=p_auth_user_id
  limit 1;

  if actor is not null then
    return actor;
  end if;

  -- Do not relink an auth identity already claimed by an employee with incomplete role data.
  if exists (select 1 from hq.employees where auth_user_id=p_auth_user_id) then
    return null;
  end if;

  -- A phone-based link is allowed only for one exact match that is already active
  -- and has an assigned, active role. Ambiguous, pending, suspended, or roleless
  -- employee records are never linked automatically.
  select count(*)
    into matched_count
  from hq.employees e
  join hq.roles r on r.id=e.primary_role_id and r.active
  where e.phone_e164=p_phone_e164
    and e.status='active';

  if matched_count <> 1 then
    return null;
  end if;

  select e.id,e.auth_user_id
    into matched_employee_id,matched_auth_user_id
  from hq.employees e
  join hq.roles r on r.id=e.primary_role_id and r.active
  where e.phone_e164=p_phone_e164
    and e.status='active'
  limit 1
  for update of e;

  if matched_auth_user_id is not null and matched_auth_user_id <> p_auth_user_id then
    return null;
  end if;

  update hq.employees
     set auth_user_id=p_auth_user_id, updated_at=now()
   where id=matched_employee_id
     and status='active'
     and (auth_user_id is null or auth_user_id=p_auth_user_id);

  if not found then
    return null;
  end if;

  select jsonb_build_object(
    'employee_id',e.id,
    'employee_code',e.employee_code,
    'name',e.display_name,
    'role',r.code,
    'status',e.status
  )
  into actor
  from hq.employees e
  join hq.roles r on r.id=e.primary_role_id
  where e.auth_user_id=p_auth_user_id
  limit 1;

  return actor;
end;
$$;

revoke all on function public.hq_actor_context_for_login_v1(uuid,text) from public,anon,authenticated;
grant execute on function public.hq_actor_context_for_login_v1(uuid,text) to service_role;

commit;
