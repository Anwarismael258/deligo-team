begin;

-- The generic authorization layer now gives FINANCE the SUPER_ADMIN effective
-- scope. These legacy RPCs also had role-literal guards, so align them too.
create or replace function public.hq_create_employee_v1(
 p_actor_auth_user_id uuid,p_auth_user_id uuid,p_display_name text,p_phone_e164 text,p_job_title text,
 p_department_code text,p_requested_role_code text,p_activate boolean default false
) returns jsonb language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare actor record; dept uuid; requested_role uuid; new_id uuid:=gen_random_uuid(); new_code text; new_status text:='invited';
begin
 select e.id employee_id,r.code role into actor from hq.employees e join hq.roles r on r.id=e.primary_role_id where e.auth_user_id=p_actor_auth_user_id and e.status='active';
 if actor.role not in ('SUPER_ADMIN','FINANCE','HUMAN_RESOURCES') then raise exception 'HQ_EMPLOYEE_ADMIN_FORBIDDEN'; end if;
 if actor.role='HUMAN_RESOURCES' and p_requested_role_code in ('SUPER_ADMIN','HUMAN_RESOURCES','FINANCE','LEGAL','TECHNOLOGY') then raise exception 'HQ_SENSITIVE_ROLE_REQUIRES_SUPER_ADMIN'; end if;
 select id into dept from hq.departments where code=p_department_code and active;
 select id into requested_role from hq.roles where code=p_requested_role_code and active;
 if dept is null or requested_role is null then raise exception 'HQ_INVALID_DEPARTMENT_OR_ROLE'; end if;
 select 'DG-'||lpad((coalesce(max(substring(employee_code from 4)::int),0)+1)::text,4,'0') into new_code from hq.employees where employee_code ~ '^DG-[0-9]+$';
 if p_activate and actor.role in ('SUPER_ADMIN','FINANCE') then new_status:='active'; end if;
 insert into hq.employees(id,employee_code,auth_user_id,legal_entity_id,department_id,display_name,phone_e164,job_title,status,primary_role_id,requested_role_code)
 values(new_id,new_code,p_auth_user_id,'10000000-0000-0000-0000-000000000001',dept,p_display_name,p_phone_e164,p_job_title,new_status,case when new_status='active' then requested_role end,p_requested_role_code);
 if new_status='active' then
  insert into hq.employee_roles(employee_id,role_id,department_id,granted_by) values(new_id,requested_role,dept,actor.employee_id);
  insert into hq.employee_platforms(employee_id,platform_id,granted_by) select new_id,id,actor.employee_id from hq.platforms on conflict do nothing;
 else
  insert into hq.approval_requests(legal_entity_id,request_type,target_type,target_id,title,status,required_approvals,requested_by,submitted_at)
  values('10000000-0000-0000-0000-000000000001','EMPLOYEE_ACCESS','employee',new_id::text,'Activar '||p_display_name,'submitted',1,actor.employee_id,now());
 end if;
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,module,target_type,target_id,result,metadata)
 values(actor.employee_id,'EMPLOYEE_CREATED','10000000-0000-0000-0000-000000000001','people','employee',new_id::text,'success',jsonb_build_object('status',new_status,'requested_role',p_requested_role_code));
 return jsonb_build_object('id',new_id,'employee_code',new_code,'status',new_status);
end $$;

create or replace function public.hq_set_employee_status_v1(p_actor_auth_user_id uuid,p_employee_id uuid,p_action text) returns jsonb
language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare actor record; target record; role_id uuid; next_status text;
begin
 select e.id employee_id,r.code role into actor from hq.employees e join hq.roles r on r.id=e.primary_role_id where e.auth_user_id=p_actor_auth_user_id and e.status='active';
 select e.*,r.code role_code into target from hq.employees e left join hq.roles r on r.id=e.primary_role_id where e.id=p_employee_id for update;
 if actor.role not in ('SUPER_ADMIN','FINANCE') then raise exception 'HQ_SUPER_ADMIN_APPROVAL_REQUIRED'; end if;
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

create or replace function public.hq_update_employee_v1(
 p_actor_auth_user_id uuid,p_employee_id uuid,p_display_name text,p_phone_e164 text,p_job_title text,
 p_department_code text,p_requested_role_code text,p_expected_updated_at timestamptz
) returns jsonb language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare actor record; target record; dept uuid; next_role uuid; changed_at timestamptz:=now();
begin
 select e.id employee_id,r.code role into actor from hq.employees e join hq.roles r on r.id=e.primary_role_id where e.auth_user_id=p_actor_auth_user_id and e.status='active';
 if actor.role not in ('SUPER_ADMIN','FINANCE','HUMAN_RESOURCES') then raise exception 'HQ_EMPLOYEE_ADMIN_FORBIDDEN'; end if;
 select e.* into target from hq.employees e where e.id=p_employee_id for update;
 if target.id is null then raise exception 'HQ_EMPLOYEE_NOT_FOUND'; end if;
 if target.updated_at<>p_expected_updated_at then raise exception 'HQ_EMPLOYEE_CONFLICT'; end if;
 if target.employee_code='DG-0001' and (p_department_code<>(select code from hq.departments where id=target.department_id) or p_requested_role_code<>target.requested_role_code) then raise exception 'HQ_FOUNDER_ACCOUNT_PROTECTED'; end if;
 if actor.role='HUMAN_RESOURCES' and p_requested_role_code in ('SUPER_ADMIN','HUMAN_RESOURCES','FINANCE','LEGAL','TECHNOLOGY') then raise exception 'HQ_SENSITIVE_ROLE_REQUIRES_SUPER_ADMIN'; end if;
 if nullif(trim(p_display_name),'') is null or nullif(trim(p_job_title),'') is null or p_phone_e164!~'^\+258[0-9]{9}$' then raise exception 'HQ_EMPLOYEE_INPUT_INVALID'; end if;
 select id into dept from hq.departments where code=p_department_code and active;
 select id into next_role from hq.roles where code=p_requested_role_code and active;
 if dept is null or next_role is null then raise exception 'HQ_INVALID_DEPARTMENT_OR_ROLE'; end if;
 update hq.employees set display_name=trim(p_display_name),phone_e164=p_phone_e164,job_title=trim(p_job_title),department_id=dept,requested_role_code=p_requested_role_code,primary_role_id=case when status='active' then next_role else primary_role_id end,updated_at=changed_at where id=p_employee_id;
 if target.status='active' then
  update hq.employee_roles set revoked_at=changed_at where employee_id=p_employee_id and revoked_at is null and role_id<>next_role;
  insert into hq.employee_roles(employee_id,role_id,department_id,granted_by) values(p_employee_id,next_role,dept,actor.employee_id) on conflict (employee_id,role_id,department_id,platform_id) do update set revoked_at=null,valid_until=null,granted_by=actor.employee_id;
 end if;
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,module,target_type,target_id,result,metadata)
 values(actor.employee_id,'EMPLOYEE_UPDATED','10000000-0000-0000-0000-000000000001','people','employee',p_employee_id::text,'success',jsonb_build_object('previous_department_id',target.department_id,'department_id',dept,'previous_role',target.requested_role_code,'role',p_requested_role_code));
 return jsonb_build_object('id',p_employee_id,'auth_user_id',target.auth_user_id,'updated_at',changed_at);
end $$;

create or replace function public.hq_log_platform_action_v1(p_actor_auth_user_id uuid,p_platform text,p_action text,p_target_type text,p_target_id text,p_metadata jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare actor record;
begin
 select e.id employee_id,r.code role into actor from hq.employees e join hq.roles r on r.id=e.primary_role_id where e.auth_user_id=p_actor_auth_user_id and e.status='active';
 if actor.employee_id is null then raise exception 'HQ_ACTOR_NOT_ACTIVE'; end if;
 if actor.role not in ('SUPER_ADMIN','FINANCE','SUPERVISOR','OPERATIONS') then raise exception 'HQ_DECISION_FORBIDDEN'; end if;
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,module,target_type,target_id,result,metadata) values(actor.employee_id,upper(p_action),'10000000-0000-0000-0000-000000000001',lower(p_platform),p_target_type,p_target_id,'success',coalesce(p_metadata,'{}'::jsonb));
 return jsonb_build_object('ok',true,'actor_role',actor.role);
end $$;

create or replace function public.hq_log_operational_action_v1(p_actor_auth_user_id uuid,p_module text,p_action text,p_target_type text,p_target_id text,p_metadata jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare actor record; allowed boolean:=false;
begin
 select e.id employee_id,r.code role into actor from hq.employees e join hq.roles r on r.id=e.primary_role_id where e.auth_user_id=p_actor_auth_user_id and e.status='active';
 if actor.employee_id is null then raise exception 'HQ_ACTOR_NOT_ACTIVE'; end if;
 allowed := actor.role in ('SUPER_ADMIN','FINANCE')
   or (p_module='support' and actor.role in ('SUPERVISOR','OPERATIONS','CUSTOMER_SUPPORT'))
   or (p_module='field' and actor.role in ('SUPERVISOR','OPERATIONS','FIELD'))
   or (p_module='marketing' and actor.role in ('SUPERVISOR','OPERATIONS','MARKETING'));
 if not allowed then raise exception 'HQ_OPERATION_FORBIDDEN'; end if;
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,module,target_type,target_id,result,metadata)
 values(actor.employee_id,upper(p_action),'10000000-0000-0000-0000-000000000001',p_module,p_target_type,p_target_id,'success',coalesce(p_metadata,'{}'::jsonb));
 return jsonb_build_object('ok',true);
end $$;

create or replace function public.hq_log_audit_export_v1(p_actor_auth_user_id uuid,p_export_kind text,p_record_count integer) returns void
language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare actor record;
begin
 select e.id as employee_id,r.code as role into actor from hq.employees e join hq.roles r on r.id=e.primary_role_id where e.auth_user_id=p_actor_auth_user_id and e.status='active';
 if actor.role not in ('SUPER_ADMIN','FINANCE','HUMAN_RESOURCES') then raise exception 'HQ_AUDIT_EXPORT_FORBIDDEN'; end if;
 if p_export_kind<>'audit_csv' or p_record_count<0 or p_record_count>500 then raise exception 'HQ_AUDIT_EXPORT_INVALID'; end if;
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,module,target_type,result,metadata) values(actor.employee_id,'AUDIT_EXPORTED','10000000-0000-0000-0000-000000000001','audit','audit_log','success',jsonb_build_object('format','csv','record_count',p_record_count));
end $$;

commit;
