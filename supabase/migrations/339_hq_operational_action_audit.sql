begin;

create or replace function public.hq_log_operational_action_v1(
  p_actor_auth_user_id uuid,p_module text,p_action text,p_target_type text,p_target_id text,p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare actor record; allowed boolean:=false;
begin
  select e.id employee_id,r.code role into actor
  from hq.employees e join hq.roles r on r.id=e.primary_role_id
  where e.auth_user_id=p_actor_auth_user_id and e.status='active';
  if actor.employee_id is null then raise exception 'HQ_ACTOR_NOT_ACTIVE'; end if;
  allowed := actor.role='SUPER_ADMIN'
    or (p_module='support' and actor.role in ('SUPERVISOR','OPERATIONS','CUSTOMER_SUPPORT'))
    or (p_module='field' and actor.role in ('SUPERVISOR','OPERATIONS','FIELD'))
    or (p_module='marketing' and actor.role in ('SUPERVISOR','OPERATIONS','MARKETING'));
  if not allowed then raise exception 'HQ_OPERATION_FORBIDDEN'; end if;
  insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,module,target_type,target_id,result,metadata)
  values(actor.employee_id,upper(p_action),'10000000-0000-0000-0000-000000000001',p_module,p_target_type,p_target_id,'success',coalesce(p_metadata,'{}'::jsonb));
  return jsonb_build_object('ok',true);
end $$;

revoke all on function public.hq_log_operational_action_v1(uuid,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.hq_log_operational_action_v1(uuid,text,text,text,text,jsonb) to service_role;

commit;
