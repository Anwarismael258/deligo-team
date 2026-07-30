begin;

alter table hq.employees add column if not exists requested_role_code text;
alter table hq.employees add column if not exists suspended_at timestamptz;
alter table hq.employees add column if not exists offboarded_at timestamptz;

create or replace function public.hq_actor_context_v1(p_auth_user_id uuid) returns jsonb
language sql stable security definer set search_path=hq,public,pg_temp as $$
 select jsonb_build_object('employee_id',e.id,'employee_code',e.employee_code,'name',e.display_name,'role',r.code,'status',e.status)
 from hq.employees e join hq.roles r on r.id=e.primary_role_id where e.auth_user_id=p_auth_user_id limit 1
$$;

create or replace function public.hq_employee_directory_v1() returns jsonb
language sql stable security definer set search_path=hq,public,pg_temp as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',e.id,'employee_code',e.employee_code,'name',e.display_name,'phone',e.phone_e164,
  'job_title',e.job_title,'department',d.name,'department_code',d.code,'role',r.code,
  'requested_role',e.requested_role_code,'status',e.status,'last_login_at',e.last_login_at,
  'created_at',e.created_at,'suspended_at',e.suspended_at,'offboarded_at',e.offboarded_at
 ) order by e.created_at), '[]'::jsonb)
 from hq.employees e left join hq.departments d on d.id=e.department_id left join hq.roles r on r.id=e.primary_role_id
$$;

create or replace function public.hq_audit_history_v1(p_limit integer default 100) returns jsonb
language sql stable security definer set search_path=hq,public,pg_temp as $$
 select coalesce(jsonb_agg(x.item order by x.occurred_at desc),'[]'::jsonb) from (
  select a.occurred_at,jsonb_build_object('id',a.id,'occurred_at',a.occurred_at,'actor',coalesce(e.display_name,'Sistema'),
   'action',a.action,'module',a.module,'target_type',a.target_type,'target_id',a.target_id,'result',a.result,
   'ip_address',a.ip_address,'metadata',a.metadata) item
  from hq.audit_logs a left join hq.employees e on e.id=a.actor_employee_id order by a.occurred_at desc limit least(greatest(p_limit,1),500)
 ) x
$$;

create or replace function public.hq_create_employee_v1(
 p_actor_auth_user_id uuid,p_auth_user_id uuid,p_display_name text,p_phone_e164 text,p_job_title text,
 p_department_code text,p_requested_role_code text,p_activate boolean default false
) returns jsonb language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare actor record; dept uuid; requested_role uuid; new_id uuid:=gen_random_uuid(); new_code text; new_status text:='invited';
begin
 select e.id employee_id,r.code role into actor from hq.employees e join hq.roles r on r.id=e.primary_role_id where e.auth_user_id=p_actor_auth_user_id and e.status='active';
 if actor.role not in ('SUPER_ADMIN','HUMAN_RESOURCES') then raise exception 'HQ_EMPLOYEE_ADMIN_FORBIDDEN'; end if;
 if actor.role='HUMAN_RESOURCES' and p_requested_role_code in ('SUPER_ADMIN','HUMAN_RESOURCES','FINANCE','LEGAL','TECHNOLOGY') then raise exception 'HQ_SENSITIVE_ROLE_REQUIRES_SUPER_ADMIN'; end if;
 select id into dept from hq.departments where code=p_department_code and active;
 select id into requested_role from hq.roles where code=p_requested_role_code and active;
 if dept is null or requested_role is null then raise exception 'HQ_INVALID_DEPARTMENT_OR_ROLE'; end if;
 select 'DG-'||lpad((coalesce(max(substring(employee_code from 4)::int),0)+1)::text,4,'0') into new_code from hq.employees where employee_code ~ '^DG-[0-9]+$';
 if p_activate and actor.role='SUPER_ADMIN' then new_status:='active'; end if;
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
 return jsonb_build_object('id',p_employee_id,'status',next_status);
end $$;

revoke all on function public.hq_actor_context_v1(uuid) from public,anon,authenticated;
revoke all on function public.hq_employee_directory_v1() from public,anon,authenticated;
revoke all on function public.hq_audit_history_v1(integer) from public,anon,authenticated;
revoke all on function public.hq_create_employee_v1(uuid,uuid,text,text,text,text,text,boolean) from public,anon,authenticated;
revoke all on function public.hq_set_employee_status_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.hq_actor_context_v1(uuid),public.hq_employee_directory_v1(),public.hq_audit_history_v1(integer),public.hq_create_employee_v1(uuid,uuid,text,text,text,text,text,boolean),public.hq_set_employee_status_v1(uuid,uuid,text) to service_role;

commit;
