begin;

create or replace function public.hq_employee_directory_v1() returns jsonb
language sql stable security definer set search_path=hq,public,pg_temp as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',e.id,'auth_user_id',e.auth_user_id,'employee_code',e.employee_code,'name',e.display_name,'phone',e.phone_e164,
  'job_title',e.job_title,'department',d.name,'department_code',d.code,'role',r.code,
  'requested_role',e.requested_role_code,'status',e.status,'last_login_at',e.last_login_at,
  'created_at',e.created_at,'updated_at',e.updated_at,'suspended_at',e.suspended_at,'offboarded_at',e.offboarded_at
 ) order by e.created_at), '[]'::jsonb)
 from hq.employees e left join hq.departments d on d.id=e.department_id left join hq.roles r on r.id=e.primary_role_id
$$;

create or replace function public.hq_update_employee_v1(
 p_actor_auth_user_id uuid,p_employee_id uuid,p_display_name text,p_phone_e164 text,p_job_title text,
 p_department_code text,p_requested_role_code text,p_expected_updated_at timestamptz
) returns jsonb language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare actor record; target record; dept uuid; next_role uuid; changed_at timestamptz:=now();
begin
 select e.id employee_id,r.code role into actor from hq.employees e join hq.roles r on r.id=e.primary_role_id where e.auth_user_id=p_actor_auth_user_id and e.status='active';
 if actor.role not in ('SUPER_ADMIN','HUMAN_RESOURCES') then raise exception 'HQ_EMPLOYEE_ADMIN_FORBIDDEN'; end if;
 select e.* into target from hq.employees e where e.id=p_employee_id for update;
 if target.id is null then raise exception 'HQ_EMPLOYEE_NOT_FOUND'; end if;
 if target.updated_at<>p_expected_updated_at then raise exception 'HQ_EMPLOYEE_CONFLICT'; end if;
 if target.employee_code='DG-0001' and (p_department_code<>(select code from hq.departments where id=target.department_id) or p_requested_role_code<>target.requested_role_code) then raise exception 'HQ_FOUNDER_ACCOUNT_PROTECTED'; end if;
 if actor.role='HUMAN_RESOURCES' and p_requested_role_code in ('SUPER_ADMIN','HUMAN_RESOURCES','FINANCE','LEGAL','TECHNOLOGY') then raise exception 'HQ_SENSITIVE_ROLE_REQUIRES_SUPER_ADMIN'; end if;
 if nullif(trim(p_display_name),'') is null or nullif(trim(p_job_title),'') is null or p_phone_e164!~'^\+258[0-9]{9}$' then raise exception 'HQ_EMPLOYEE_INPUT_INVALID'; end if;
 select id into dept from hq.departments where code=p_department_code and active;
 select id into next_role from hq.roles where code=p_requested_role_code and active;
 if dept is null or next_role is null then raise exception 'HQ_INVALID_DEPARTMENT_OR_ROLE'; end if;
 update hq.employees set display_name=trim(p_display_name),phone_e164=p_phone_e164,job_title=trim(p_job_title),department_id=dept,
  requested_role_code=p_requested_role_code,primary_role_id=case when status='active' then next_role else primary_role_id end,updated_at=changed_at where id=p_employee_id;
 if target.status='active' then
  update hq.employee_roles set revoked_at=changed_at where employee_id=p_employee_id and revoked_at is null and role_id<>next_role;
  insert into hq.employee_roles(employee_id,role_id,department_id,granted_by) values(p_employee_id,next_role,dept,actor.employee_id)
   on conflict (employee_id,role_id,department_id,platform_id) do update set revoked_at=null,valid_until=null,granted_by=actor.employee_id;
 end if;
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,module,target_type,target_id,result,metadata)
 values(actor.employee_id,'EMPLOYEE_UPDATED','10000000-0000-0000-0000-000000000001','people','employee',p_employee_id::text,'success',
  jsonb_build_object('previous_department_id',target.department_id,'department_id',dept,'previous_role',target.requested_role_code,'role',p_requested_role_code));
 return jsonb_build_object('id',p_employee_id,'auth_user_id',target.auth_user_id,'updated_at',changed_at);
end $$;

revoke all on function public.hq_update_employee_v1(uuid,uuid,text,text,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.hq_update_employee_v1(uuid,uuid,text,text,text,text,text,timestamptz) to service_role;

commit;
