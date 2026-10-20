begin;

create or replace function public.hq_actor_context_for_login_v1(
  p_auth_user_id uuid,
  p_phone_e164 text
) returns jsonb
language plpgsql
security definer
set search_path=hq,public,pg_temp
as $$
declare actor jsonb;
begin
  if p_auth_user_id is null or p_phone_e164 is null
     or p_phone_e164 !~ '^[+][0-9]{12}$' then
    return null;
  end if;

  -- Authenticated callers may only resolve their own identity. The backend
  -- service role remains allowed for server-side administration flows.
  if coalesce(auth.role(),'') <> 'service_role'
     and auth.uid() is distinct from p_auth_user_id then
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
     and e.phone_e164=p_phone_e164
   limit 1;

  return actor;
end;
$$;

revoke all on function public.hq_actor_context_for_login_v1(uuid,text) from public,anon;
grant execute on function public.hq_actor_context_for_login_v1(uuid,text) to authenticated,service_role;

commit;
