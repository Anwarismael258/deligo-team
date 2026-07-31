begin;

create or replace function public.hq_log_audit_export_v1(
  p_actor_auth_user_id uuid,
  p_export_kind text,
  p_record_count integer
) returns void
language plpgsql
security definer
set search_path=hq,public,pg_temp
as $$
declare
  actor record;
begin
  select e.id as employee_id, r.code as role
    into actor
  from hq.employees e
  join hq.roles r on r.id = e.primary_role_id
  where e.auth_user_id = p_actor_auth_user_id
    and e.status = 'active';

  if actor.role not in ('SUPER_ADMIN', 'HUMAN_RESOURCES') then
    raise exception 'HQ_AUDIT_EXPORT_FORBIDDEN';
  end if;

  if p_export_kind <> 'audit_csv' or p_record_count < 0 or p_record_count > 500 then
    raise exception 'HQ_AUDIT_EXPORT_INVALID';
  end if;

  insert into hq.audit_logs(
    actor_employee_id, action, legal_entity_id, module, target_type, result, metadata
  ) values (
    actor.employee_id, 'AUDIT_EXPORTED', '10000000-0000-0000-0000-000000000001',
    'audit', 'audit_log', 'success', jsonb_build_object('format', 'csv', 'record_count', p_record_count)
  );
end;
$$;

revoke all on function public.hq_log_audit_export_v1(uuid,text,integer) from public, anon, authenticated;
grant execute on function public.hq_log_audit_export_v1(uuid,text,integer) to service_role;

commit;
