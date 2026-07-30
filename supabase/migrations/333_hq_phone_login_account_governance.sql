begin;

update hq.employees set phone_e164=case employee_code
 when 'DG-0001' then '+258849990001' when 'DG-0002' then '+258849990002' when 'DG-0003' then '+258849990003'
 when 'DG-0101' then '+258849990004' when 'DG-0102' then '+258849990005' when 'DG-0103' then '+258849990006'
 when 'DG-0104' then '+258849990007' when 'DG-0105' then '+258849990008' when 'DG-0201' then '+258849990009'
 when 'DG-0202' then '+258849990010' when 'DG-0203' then '+258849990011' when 'DG-0204' then '+258849990012'
 when 'DG-0205' then '+258849990013' when 'DG-0206' then '+258849990014' when 'DG-0207' then '+258849990015'
 when 'DG-0208' then '+258849990016' end
where employee_code in ('DG-0001','DG-0002','DG-0003','DG-0101','DG-0102','DG-0103','DG-0104','DG-0105','DG-0201','DG-0202','DG-0203','DG-0204','DG-0205','DG-0206','DG-0207','DG-0208');

create unique index if not exists hq_employees_active_phone_unique on hq.employees(phone_e164) where status<>'offboarded';

insert into hq.permissions(code,module,action,data_class,description) values
 ('employee.create','people','create','personal','Criar cadastro de trabalhador'),
 ('employee.edit','people','edit','personal','Editar cadastro do trabalhador'),
 ('employee.suspend','security','suspend','restricted','Suspender acesso do trabalhador'),
 ('employee.offboarding.initiate','hr','create','personal','Iniciar offboarding'),
 ('employee.offboarding.approve','security','approve','restricted','Aprovar encerramento de acesso'),
 ('employee.archive','people','archive','restricted','Arquivar conta preservando histórico')
on conflict(code) do update set module=excluded.module,action=excluded.action,data_class=excluded.data_class,description=excluded.description;

insert into hq.role_permissions(role_id,permission_id)
select '50000000-0000-0000-0000-000000000001',id from hq.permissions
where code=any(array['employee.create','employee.edit','employee.suspend','employee.offboarding.initiate','employee.offboarding.approve','employee.archive'])
on conflict do nothing;

insert into hq.role_permissions(role_id,permission_id)
select '50000000-0000-0000-0000-000000000005',id from hq.permissions
where code=any(array['employee.create','employee.edit','employee.offboarding.initiate'])
on conflict do nothing;

commit;
