-- Employee onboarding uses the six Central cargos while retaining the
-- existing internal role catalogue. No data is removed or rewritten.
create or replace function public.hq_create_employee_v1(
 p_actor_auth_user_id uuid,p_auth_user_id uuid,p_display_name text,p_phone_e164 text,p_job_title text,
 p_department_code text,p_requested_role_code text,p_activate boolean default false
) returns jsonb language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare actor record; dept uuid; requested_role uuid; new_id uuid:=gen_random_uuid(); new_code text; new_status text:='invited';
begin
 select e.id employee_id,r.code role into actor
 from hq.employees e join hq.roles r on r.id=e.primary_role_id
 where e.auth_user_id=p_actor_auth_user_id and e.status='active';
 if actor.role not in ('SUPER_ADMIN','HUMAN_RESOURCES','FINANCE_DIRECTOR','FINANCE','OPERATIONS_SUPERVISOR','SUPERVISOR') then
   raise exception 'HQ_EMPLOYEE_ADMIN_FORBIDDEN';
 end if;
 if actor.role <> 'SUPER_ADMIN' and p_requested_role_code='SUPER_ADMIN' then
   raise exception 'HQ_SENSITIVE_ROLE_REQUIRES_SUPER_ADMIN';
 end if;
 if nullif(trim(p_display_name),'') is null or nullif(trim(p_job_title),'') is null or p_phone_e164 !~ '^\+258[0-9]{9}$' then
   raise exception 'HQ_EMPLOYEE_INPUT_INVALID';
 end if;
 select id into dept from hq.departments where code=p_department_code and active;
 select id into requested_role from hq.roles where code=p_requested_role_code and active;
 if dept is null or requested_role is null then raise exception 'HQ_INVALID_DEPARTMENT_OR_ROLE'; end if;
 select 'DG-'||lpad((coalesce(max(substring(employee_code from 4)::int),0)+1)::text,4,'0')
 into new_code from hq.employees where employee_code ~ '^DG-[0-9]+$';
 if p_activate and actor.role='SUPER_ADMIN' then new_status:='active'; end if;
 insert into hq.employees(id,employee_code,auth_user_id,legal_entity_id,department_id,display_name,phone_e164,job_title,status,primary_role_id,requested_role_code)
 values(new_id,new_code,p_auth_user_id,'10000000-0000-0000-0000-000000000001',dept,trim(p_display_name),p_phone_e164,trim(p_job_title),new_status,case when new_status='active' then requested_role end,p_requested_role_code);
 if new_status='active' then
   insert into hq.employee_roles(employee_id,role_id,department_id,granted_by)
   values(new_id,requested_role,dept,actor.employee_id);
   insert into hq.employee_platforms(employee_id,platform_id,granted_by)
   select new_id,id,actor.employee_id from hq.platforms on conflict do nothing;
 else
   insert into hq.approval_requests(legal_entity_id,request_type,target_type,target_id,title,status,required_approvals,requested_by,submitted_at)
   values('10000000-0000-0000-0000-000000000001','EMPLOYEE_ACCESS','employee',new_id::text,'Activar '||trim(p_display_name),'submitted',1,actor.employee_id,now());
 end if;
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,module,target_type,target_id,result,metadata)
 values(actor.employee_id,'EMPLOYEE_CREATED','10000000-0000-0000-0000-000000000001','people','employee',new_id::text,'success',jsonb_build_object('status',new_status,'requested_role',p_requested_role_code));
 return jsonb_build_object('id',new_id,'employee_code',new_code,'status',new_status);
end $$;

revoke all on function public.hq_create_employee_v1(uuid,uuid,text,text,text,text,text,boolean) from public,anon,authenticated;
grant execute on function public.hq_create_employee_v1(uuid,uuid,text,text,text,text,text,boolean) to service_role;
