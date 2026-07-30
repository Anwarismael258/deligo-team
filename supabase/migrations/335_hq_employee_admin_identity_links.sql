begin;

create or replace function public.hq_employee_directory_v1() returns jsonb
language sql stable security definer set search_path=hq,public,pg_temp as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',e.id,'auth_user_id',e.auth_user_id,'employee_code',e.employee_code,'name',e.display_name,'phone',e.phone_e164,
  'job_title',e.job_title,'department',d.name,'department_code',d.code,'role',r.code,
  'requested_role',e.requested_role_code,'status',e.status,'last_login_at',e.last_login_at,
  'created_at',e.created_at,'suspended_at',e.suspended_at,'offboarded_at',e.offboarded_at
 ) order by e.created_at), '[]'::jsonb)
 from hq.employees e left join hq.departments d on d.id=e.department_id left join hq.roles r on r.id=e.primary_role_id
$$;

create or replace function public.hq_set_employee_status_v1(p_actor_auth_user_id uuid,p_employee_id uuid,p_action text) returns jsonb
language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare actor record; target record; role_id uuid; next_status text;
begin
 select e.id employee_id,r.code role into actor from hq.employees e join hq.roles r on r.id=e.primary_role_id where e.auth_user_id=p_actor_auth_user_id and e.status='active';
 select e.*,r.code role_code into target from hq.employees e left join hq.roles r on r.id=e.primary_role_id where e.id=p_employee_id for update;
 if actor.role<>'SUPER_ADMIN' then raise exception 'HQ_SUPER_ADMIN_APPROVAL_REQUIRED'; end if;
 if target.employee_code='DG-0001' then raise exception 'HQ_FOUNDER_ACCOUNT_PROTECTED'; end if;
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
end $$;

revoke all on function public.hq_employee_directory_v1(),public.hq_set_employee_status_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.hq_employee_directory_v1(),public.hq_set_employee_status_v1(uuid,uuid,text) to service_role;

commit;
