begin;
alter table hq.employees add column if not exists primary_role_id uuid references hq.roles(id);
update hq.roles set code='FINANCE', name='Finanças' where id='50000000-0000-0000-0000-000000000002';
update hq.roles set code='SUPERVISOR', name='Supervisor' where id='50000000-0000-0000-0000-000000000003';
insert into hq.employees (id, employee_code, legal_entity_id, department_id, display_name, corporate_email, job_title, status) values
  ('40000000-0000-0000-0000-000000000101','DG-0101','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000009','Admin DeliGo Field','field.admin@staging.deligo.co.mz','Field','active'),
  ('40000000-0000-0000-0000-000000000102','DG-0102','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000008','Agente de Marketing','marketing@staging.deligo.co.mz','Marketing','active'),
  ('40000000-0000-0000-0000-000000000103','DG-0103','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000009','Agente Do Teste','field.agent@staging.deligo.co.mz','Field','active'),
  ('40000000-0000-0000-0000-000000000104','DG-0104','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000010','Agente Suporte','support@staging.deligo.co.mz','Apoio ao Cliente','active'),
  ('40000000-0000-0000-0000-000000000105','DG-0105','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000009','Juvêncio Antônio','juvencio@staging.deligo.co.mz','Field','active')
on conflict (employee_code) do update set display_name=excluded.display_name, corporate_email=excluded.corporate_email, department_id=excluded.department_id, job_title=excluded.job_title;
update hq.employees e set corporate_email=v.email from (values
  ('DG-0001','anwar@staging.deligo.co.mz'),('DG-0002','sara@staging.deligo.co.mz'),('DG-0003','sansao@staging.deligo.co.mz')
) v(code,email) where e.employee_code=v.code;
update hq.employees e set auth_user_id=u.id
from auth.users u where lower(u.email)=lower(e.corporate_email) and e.corporate_email like '%@staging.deligo.co.mz';
update hq.employees set primary_role_id=case employee_code
  when 'DG-0001' then '50000000-0000-0000-0000-000000000001'::uuid
  when 'DG-0002' then '50000000-0000-0000-0000-000000000002'::uuid
  when 'DG-0003' then '50000000-0000-0000-0000-000000000003'::uuid
  when 'DG-0101' then '50000000-0000-0000-0000-000000000008'::uuid
  when 'DG-0102' then '50000000-0000-0000-0000-000000000007'::uuid
  when 'DG-0103' then '50000000-0000-0000-0000-000000000008'::uuid
  when 'DG-0104' then '50000000-0000-0000-0000-000000000009'::uuid
  when 'DG-0105' then '50000000-0000-0000-0000-000000000008'::uuid
end where employee_code in ('DG-0001','DG-0002','DG-0003','DG-0101','DG-0102','DG-0103','DG-0104','DG-0105');
insert into hq.role_permissions (role_id, permission_id)
select '50000000-0000-0000-0000-000000000007', id from hq.permissions
where code=any(array['platforms.view','marketing.view','marketing.manage','marketing.publish','reports.view'])
on conflict (role_id, permission_id) do nothing;
insert into hq.role_permissions (role_id, permission_id)
select '50000000-0000-0000-0000-000000000008', id from hq.permissions
where code=any(array['platforms.view','field.view','field.manage','acquisition.view','reports.view'])
on conflict (role_id, permission_id) do nothing;
insert into hq.role_permissions (role_id, permission_id)
select '50000000-0000-0000-0000-000000000009', id from hq.permissions
where code=any(array['platforms.view','support.view','support.manage','reports.view'])
on conflict (role_id, permission_id) do nothing;
delete from hq.employee_roles where employee_id in (
  '40000000-0000-0000-0000-000000000101','40000000-0000-0000-0000-000000000102','40000000-0000-0000-0000-000000000103','40000000-0000-0000-0000-000000000104','40000000-0000-0000-0000-000000000105'
);
insert into hq.employee_roles (employee_id, role_id, department_id, granted_by)
select e.id, e.primary_role_id, e.department_id, '40000000-0000-0000-0000-000000000001'::uuid
from hq.employees e where e.employee_code in ('DG-0101','DG-0102','DG-0103','DG-0104','DG-0105');
insert into hq.employee_platforms (employee_id, platform_id, granted_by)
select e.id, '20000000-0000-0000-0000-000000000001'::uuid, '40000000-0000-0000-0000-000000000001'::uuid
from hq.employees e where e.employee_code in ('DG-0101','DG-0102','DG-0103','DG-0104','DG-0105')
on conflict (employee_id, platform_id) do nothing;
create or replace function hq.enforce_single_active_role() returns trigger
language plpgsql security definer set search_path=hq,pg_temp as $$
begin
  if new.revoked_at is null and (new.valid_until is null or new.valid_until > now()) and exists (
    select 1 from hq.employee_roles er where er.employee_id=new.employee_id and er.id<>new.id
      and er.revoked_at is null and (er.valid_until is null or er.valid_until > now())
  ) then raise exception 'HQ_ONE_ACTIVE_ROLE_PER_EMPLOYEE'; end if;
  if new.role_id<>(select primary_role_id from hq.employees where id=new.employee_id) then
    raise exception 'HQ_ROLE_MUST_MATCH_PRIMARY_ROLE'; end if;
  return new;
end $$;
drop trigger if exists enforce_single_active_role on hq.employee_roles;
create trigger enforce_single_active_role before insert or update on hq.employee_roles
for each row execute function hq.enforce_single_active_role();
revoke all on function hq.enforce_single_active_role() from public, anon, authenticated;
grant execute on function hq.enforce_single_active_role() to service_role;
commit;
