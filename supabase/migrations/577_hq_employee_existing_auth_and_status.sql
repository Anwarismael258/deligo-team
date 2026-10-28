begin;

-- A conta de uma plataforma pode já existir em auth.users. A Central deve
-- associar essa identidade ao trabalhador sem criar outra conta nem alterar
-- os papéis que essa pessoa tem nas plataformas.
create or replace function public.hq_create_employee_v1(
 p_actor_auth_user_id uuid,p_auth_user_id uuid,p_display_name text,p_phone_e164 text,p_job_title text,
 p_department_code text,p_requested_role_code text,p_activate boolean default false
) returns jsonb language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare actor record; dept uuid; requested_role uuid; new_id uuid:=gen_random_uuid(); new_code text; new_status text:='invited';
begin
 select e.id employee_id,
        coalesce(primary_role.code,assigned_role.code) role_code
 into actor
 from hq.employees e
 left join hq.roles primary_role on primary_role.id=e.primary_role_id
 left join lateral (
   select r.code
   from hq.employee_roles er
   join hq.roles r on r.id=er.role_id and r.active
   where er.employee_id=e.id and er.revoked_at is null
     and (er.valid_until is null or er.valid_until>now())
   order by case when r.code='SUPER_ADMIN' then 0 else 1 end, er.created_at desc
   limit 1
 ) assigned_role on true
 where e.auth_user_id=p_actor_auth_user_id and e.status='active';
 if actor.employee_id is null then raise exception 'HQ_EMPLOYEE_ADMIN_FORBIDDEN'; end if;
 if actor.role_code not in ('SUPER_ADMIN','HUMAN_RESOURCES','FINANCE_DIRECTOR','FINANCE','OPERATIONS_SUPERVISOR','SUPERVISOR') then
   raise exception 'HQ_EMPLOYEE_ADMIN_FORBIDDEN';
 end if;
 if actor.role_code <> 'SUPER_ADMIN' and p_requested_role_code='SUPER_ADMIN' then
   raise exception 'HQ_SENSITIVE_ROLE_REQUIRES_SUPER_ADMIN';
 end if;
 if nullif(trim(p_display_name),'') is null or nullif(trim(p_job_title),'') is null or p_phone_e164 !~ '^\+258[0-9]{9}$' then
   raise exception 'HQ_EMPLOYEE_INPUT_INVALID';
 end if;
 select id into dept from hq.departments where code=p_department_code and active;
 select id into requested_role from hq.roles where code=p_requested_role_code and active;
 if dept is null or requested_role is null then raise exception 'HQ_INVALID_DEPARTMENT_OR_ROLE'; end if;
 if exists(select 1 from hq.employees where auth_user_id=p_auth_user_id and status<>'offboarded') then
   raise exception 'HQ_EMPLOYEE_AUTH_ALREADY_LINKED';
 end if;
 select 'DG-'||lpad((coalesce(max(substring(employee_code from 4)::int),0)+1)::text,4,'0')
 into new_code from hq.employees where employee_code ~ '^DG-[0-9]+$';
 if p_activate and actor.role_code='SUPER_ADMIN' then new_status:='active'; end if;
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
 values(actor.employee_id,'EMPLOYEE_CREATED','10000000-0000-0000-0000-000000000001','people','employee',new_id::text,'success',jsonb_build_object('status',new_status,'requested_role',p_requested_role_code,'existing_auth_identity',true));
 return jsonb_build_object('id',new_id,'employee_code',new_code,'status',new_status,'auth_user_id',p_auth_user_id,'role',p_requested_role_code);
end $$;

-- Suspender/arquivar revoga apenas o acesso à Central. A identidade e os
-- dados das cinco plataformas permanecem intactos.
create or replace function public.hq_set_employee_status_v1(p_actor_auth_user_id uuid,p_employee_id uuid,p_action text) returns jsonb
language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare actor record; target record; role_id uuid; next_status text;
begin
 select e.id employee_id into actor
 from hq.employees e
 where e.auth_user_id=p_actor_auth_user_id and e.status='active'
   and (
     exists(select 1 from hq.roles r where r.id=e.primary_role_id and r.code='SUPER_ADMIN' and r.active)
     or exists(select 1 from hq.employee_roles er join hq.roles r on r.id=er.role_id
               where er.employee_id=e.id and er.revoked_at is null and r.code='SUPER_ADMIN' and r.active
                 and (er.valid_until is null or er.valid_until>now()))
   );
 if actor.employee_id is null then raise exception 'HQ_SUPER_ADMIN_APPROVAL_REQUIRED'; end if;
 select e.*,r.code role_code into target
 from hq.employees e left join hq.roles r on r.id=e.primary_role_id
 where e.id=p_employee_id for update;
 if target.id is null then raise exception 'HQ_EMPLOYEE_NOT_FOUND'; end if;
 if target.employee_code='DG-0001' then raise exception 'HQ_FOUNDER_ACCOUNT_PROTECTED'; end if;
 if p_action='activate' then
   select id into role_id from hq.roles where code=target.requested_role_code and active;
   if role_id is null then raise exception 'HQ_ROLE_REQUIRED'; end if;
   update hq.employees set status='active',primary_role_id=role_id,suspended_at=null,offboarded_at=null,updated_at=now() where id=p_employee_id;
   insert into hq.employee_roles(employee_id,role_id,department_id,granted_by) values(p_employee_id,role_id,target.department_id,actor.employee_id) on conflict do nothing;
   insert into hq.employee_platforms(employee_id,platform_id,granted_by) select p_employee_id,id,actor.employee_id from hq.platforms on conflict do nothing;
   next_status:='active';
 elsif p_action='suspend' then
   update hq.employees set status='suspended',suspended_at=now(),updated_at=now() where id=p_employee_id; next_status:='suspended';
 elsif p_action='reactivate' then
   update hq.employees set status='active',suspended_at=null,updated_at=now() where id=p_employee_id; next_status:='active';
 elsif p_action='archive' then
   update hq.employees set status='offboarded',offboarded_at=now(),updated_at=now() where id=p_employee_id;
   update hq.employee_roles set revoked_at=now() where employee_id=p_employee_id and revoked_at is null;
   update hq.employee_platforms set revoked_at=now() where employee_id=p_employee_id and revoked_at is null;
   next_status:='offboarded';
 else raise exception 'HQ_INVALID_ACCOUNT_ACTION'; end if;
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,module,target_type,target_id,result,metadata)
 values(actor.employee_id,'EMPLOYEE_'||upper(p_action),'10000000-0000-0000-0000-000000000001','people','employee',p_employee_id::text,'success',jsonb_build_object('previous_status',target.status,'new_status',next_status));
 return jsonb_build_object('id',p_employee_id,'auth_user_id',target.auth_user_id,'status',next_status,'role',coalesce(target.requested_role_code,target.role_code));
end $$;

revoke all on function public.hq_create_employee_v1(uuid,uuid,text,text,text,text,text,boolean),public.hq_set_employee_status_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.hq_create_employee_v1(uuid,uuid,text,text,text,text,text,boolean),public.hq_set_employee_status_v1(uuid,uuid,text) to service_role;

commit;
