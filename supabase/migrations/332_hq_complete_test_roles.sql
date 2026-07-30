begin;

update hq.roles set code='ACCOUNTING', name='Contabilidade' where id='50000000-0000-0000-0000-000000000004';
update hq.roles set code='HUMAN_RESOURCES', name='Recursos Humanos' where id='50000000-0000-0000-0000-000000000005';
update hq.roles set code='LEGAL', name='Jurídico' where id='50000000-0000-0000-0000-000000000006';

insert into hq.roles (id,legal_entity_id,code,name,scope,system_role) values
 ('50000000-0000-0000-0000-000000000012','10000000-0000-0000-0000-000000000001','OPERATIONS','Operações','department',true),
 ('50000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000001','PROCUREMENT','Compras','department',true),
 ('50000000-0000-0000-0000-000000000014','10000000-0000-0000-0000-000000000001','ASSETS_LOGISTICS','Património e Logística','department',true)
on conflict (legal_entity_id,code) do update set name=excluded.name,scope=excluded.scope;

insert into hq.employees (id,employee_code,legal_entity_id,department_id,display_name,corporate_email,job_title,status,primary_role_id) values
 ('40000000-0000-0000-0000-000000000201','DG-0201','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003','Contabilista de Teste','accounting@staging.deligo.co.mz','Contabilidade','active','50000000-0000-0000-0000-000000000004'),
 ('40000000-0000-0000-0000-000000000202','DG-0202','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000005','Recursos Humanos de Teste','hr@staging.deligo.co.mz','Recursos Humanos','active','50000000-0000-0000-0000-000000000005'),
 ('40000000-0000-0000-0000-000000000203','DG-0203','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000006','Jurídico de Teste','legal@staging.deligo.co.mz','Jurídico','active','50000000-0000-0000-0000-000000000006'),
 ('40000000-0000-0000-0000-000000000204','DG-0204','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000004','Operações de Teste','operations@staging.deligo.co.mz','Operações','active','50000000-0000-0000-0000-000000000012'),
 ('40000000-0000-0000-0000-000000000205','DG-0205','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000011','Aquisição de Parceiros de Teste','acquisition@staging.deligo.co.mz','Aquisição de Parceiros','active','50000000-0000-0000-0000-000000000010'),
 ('40000000-0000-0000-0000-000000000206','DG-0206','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000012','Embaixador de Teste','ambassador@staging.deligo.co.mz','Embaixadores','active','50000000-0000-0000-0000-000000000011'),
 ('40000000-0000-0000-0000-000000000207','DG-0207','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000013','Compras de Teste','procurement@staging.deligo.co.mz','Compras','active','50000000-0000-0000-0000-000000000013'),
 ('40000000-0000-0000-0000-000000000208','DG-0208','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000014','Património e Logística de Teste','assets@staging.deligo.co.mz','Património e Logística','active','50000000-0000-0000-0000-000000000014')
on conflict (employee_code) do update set display_name=excluded.display_name,corporate_email=excluded.corporate_email,department_id=excluded.department_id,job_title=excluded.job_title,primary_role_id=excluded.primary_role_id;

update hq.employees e set auth_user_id=u.id from auth.users u
where lower(u.email)=lower(e.corporate_email) and e.employee_code between 'DG-0201' and 'DG-0208';

insert into hq.employee_roles (employee_id,role_id,department_id,granted_by)
select e.id,e.primary_role_id,e.department_id,'40000000-0000-0000-0000-000000000001'::uuid from hq.employees e
where e.employee_code between 'DG-0201' and 'DG-0208'
on conflict (employee_id,role_id,department_id,platform_id) do nothing;

insert into hq.employee_platforms (employee_id,platform_id,granted_by)
select e.id,p.id,'40000000-0000-0000-0000-000000000001'::uuid from hq.employees e cross join hq.platforms p
where e.employee_code between 'DG-0201' and 'DG-0208'
on conflict (employee_id,platform_id) do nothing;

insert into hq.role_permissions (role_id,permission_id)
select '50000000-0000-0000-0000-000000000010',id from hq.permissions where code=any(array['platforms.view','acquisition.view','acquisition.manage','reports.view']) on conflict do nothing;
insert into hq.role_permissions (role_id,permission_id)
select '50000000-0000-0000-0000-000000000011',id from hq.permissions where code=any(array['platforms.view','ambassadors.view','ambassadors.manage','reports.view']) on conflict do nothing;
insert into hq.role_permissions (role_id,permission_id)
select '50000000-0000-0000-0000-000000000012',id from hq.permissions where code=any(array['platforms.view','people.view','operations.view','tasks.assign','field.view','support.view','marketing.view','acquisition.view','reports.view']) on conflict do nothing;
insert into hq.role_permissions (role_id,permission_id)
select '50000000-0000-0000-0000-000000000013',id from hq.permissions where code=any(array['platforms.view','procurement.view','procurement.manage','finance.expense.create','reports.view']) on conflict do nothing;
insert into hq.role_permissions (role_id,permission_id)
select '50000000-0000-0000-0000-000000000014',id from hq.permissions where code=any(array['platforms.view','assets.view','assets.manage','reports.view']) on conflict do nothing;

commit;
