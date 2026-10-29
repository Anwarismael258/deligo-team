CREATE OR REPLACE FUNCTION public.hq_set_employee_status_v1(p_actor_auth_user_id uuid, p_employee_id uuid, p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'hq', 'public', 'pg_temp'
AS $function$
declare actor record; target record; role_id uuid; next_status text;
begin
 select e.id employee_id,r.code role into actor from hq.employees e join hq.roles r on r.id=e.primary_role_id where e.auth_user_id=p_actor_auth_user_id and e.status='active';
 select e.*,r.code role_code into target from hq.employees e left join hq.roles r on r.id=e.primary_role_id where e.id=p_employee_id for update of e;
 if actor.employee_id is null or actor.role not in ('SUPER_ADMIN','FINANCE') then raise exception 'HQ_SUPER_ADMIN_APPROVAL_REQUIRED'; end if;
 if target.id is null then raise exception 'HQ_EMPLOYEE_NOT_FOUND'; end if;
 if p_action not in ('activate','suspend','reactivate','archive') then raise exception 'HQ_INVALID_ACCOUNT_ACTION'; end if;
 if p_action in ('suspend','archive','reactivate') and actor.role<>'SUPER_ADMIN' then raise exception 'HQ_SUPER_ADMIN_APPROVAL_REQUIRED'; end if;
 if target.id=actor.employee_id or target.employee_code='DG-0001' then raise exception 'HQ_FOUNDER_ACCOUNT_PROTECTED'; end if;
 if p_action='activate' and target.status not in ('invited','active') then raise exception 'HQ_INVALID_STATUS_TRANSITION'; end if;
 if p_action='reactivate' and target.status<>'suspended' then raise exception 'HQ_INVALID_STATUS_TRANSITION'; end if;
 if p_action='suspend' and target.status not in ('active','suspended') then raise exception 'HQ_INVALID_STATUS_TRANSITION'; end if;
 if p_action='activate' then
  select id into role_id from hq.roles where code=target.requested_role_code and active;
  if role_id is null then raise exception 'HQ_ROLE_REQUIRED'; end if;
  update hq.employees set status='active',primary_role_id=role_id,suspended_at=null,offboarded_at=null,updated_at=now() where id=p_employee_id;
  insert into hq.employee_roles(employee_id,role_id,department_id,granted_by) values(p_employee_id,role_id,target.department_id,actor.employee_id) on conflict do nothing;
  insert into hq.employee_platforms(employee_id,platform_id,granted_by) select p_employee_id,id,actor.employee_id from hq.platforms on conflict do nothing;
  next_status:='active';
 elsif p_action='suspend' then update hq.employees set status='suspended',suspended_at=now(),updated_at=now() where id=p_employee_id; next_status:='suspended';
 elsif p_action='reactivate' then update hq.employees set status='active',suspended_at=null,updated_at=now() where id=p_employee_id; next_status:='active';
 elsif p_action='archive' then update hq.employees set status='offboarded',offboarded_at=now(),updated_at=now() where id=p_employee_id; update hq.employee_roles set revoked_at=now() where employee_id=p_employee_id and revoked_at is null; update hq.employee_platforms set revoked_at=now() where employee_id=p_employee_id and revoked_at is null; next_status:='offboarded';
 else raise exception 'HQ_INVALID_ACCOUNT_ACTION'; end if;
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,module,target_type,target_id,result,metadata)
 values(actor.employee_id,'EMPLOYEE_'||upper(p_action),'10000000-0000-0000-0000-000000000001','people','employee',p_employee_id::text,'success',jsonb_build_object('previous_status',target.status,'new_status',next_status));
 return jsonb_build_object('id',p_employee_id,'auth_user_id',target.auth_user_id,'status',next_status,'role',coalesce(target.requested_role_code,target.role_code));
end $function$;
revoke all on function public.hq_set_employee_status_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.hq_set_employee_status_v1(uuid,uuid,text) to service_role;

