begin;

insert into hq.permissions(code,module,action,data_class,description) values
 ('users.view','users','view','personal','Consultar trabalhadores e colaboradores'),
 ('users.create','users','create','personal','Criar colaboradores'),
 ('users.edit','users','edit','personal','Editar colaboradores'),
 ('users.suspend','users','suspend','restricted','Suspender ou reativar contas'),
 ('finance.createExpense','finance','createExpense','financial','Criar despesas e pedidos financeiros'),
 ('finance.approvePayment','finance','approvePayment','financial','Aprovar ou rejeitar pagamentos'),
 ('hr.viewEmployees','hr','viewEmployees','personal','Consultar dados profissionais de colaboradores'),
 ('hr.viewSalary','hr','viewSalary','restricted','Consultar salários e payroll'),
 ('hr.approveLeave','hr','approveLeave','personal','Aprovar pedidos de férias e licenças'),
 ('support.viewTickets','support','viewTickets','personal','Consultar tickets autorizados'),
 ('support.reply','support','reply','personal','Responder tickets autorizados'),
 ('support.close','support','close','personal','Resolver e encerrar tickets autorizados'),
 ('field.createVisit','field','createVisit','internal','Criar e gerir visitas Field'),
 ('field.submitKyc','field','submitKyc','personal','Submeter KYC recolhido no terreno'),
 ('field.approveKyc','field','approveKyc','restricted','Aprovar ou rejeitar KYC de outro colaborador'),
 ('legal.viewContracts','legal','viewContracts','legal','Consultar contratos'),
 ('legal.approveContract','legal','approveContract','restricted','Aprovar estado de contratos'),
 ('platform.manage','platform','manage','restricted','Gerir operações das plataformas atribuídas'),
 ('settings.manage','settings','manage','restricted','Gerir cargos, permissões e configurações')
on conflict(code) do update set module=excluded.module,action=excluded.action,data_class=excluded.data_class,description=excluded.description;

insert into hq.role_permissions(role_id,permission_id)
select r.id,p.id from hq.roles r cross join hq.permissions p where r.code='SUPER_ADMIN'
on conflict(role_id,permission_id) do update set effect='allow';

with grants(role_code,permission_code) as(values
 ('HUMAN_RESOURCES','users.view'),('HUMAN_RESOURCES','users.create'),('HUMAN_RESOURCES','users.edit'),('HUMAN_RESOURCES','hr.viewEmployees'),('HUMAN_RESOURCES','hr.viewSalary'),('HUMAN_RESOURCES','hr.approveLeave'),
 ('FINANCE','finance.view'),('FINANCE','finance.createExpense'),('FINANCE','finance.approvePayment'),
 ('ACCOUNTING','finance.view'),
 ('CUSTOMER_SUPPORT','support.viewTickets'),('CUSTOMER_SUPPORT','support.reply'),('CUSTOMER_SUPPORT','support.close'),
 ('FINANCE','support.viewTickets'),('FINANCE','support.reply'),('TECHNOLOGY','support.viewTickets'),('TECHNOLOGY','support.reply'),('HUMAN_RESOURCES','support.viewTickets'),('HUMAN_RESOURCES','support.reply'),('LEGAL','support.viewTickets'),('LEGAL','support.reply'),('COMPLIANCE','support.viewTickets'),('COMPLIANCE','support.reply'),
 ('FIELD','field.view'),('FIELD','field.createVisit'),('FIELD','field.submitKyc'),
 ('SUPERVISOR','users.view'),('SUPERVISOR','support.viewTickets'),('SUPERVISOR','support.reply'),('SUPERVISOR','support.close'),('SUPERVISOR','field.view'),('SUPERVISOR','field.createVisit'),('SUPERVISOR','field.submitKyc'),('SUPERVISOR','field.approveKyc'),('SUPERVISOR','platform.manage'),
 ('OPERATIONS','users.view'),('OPERATIONS','support.viewTickets'),('OPERATIONS','support.reply'),('OPERATIONS','support.close'),('OPERATIONS','field.view'),('OPERATIONS','field.createVisit'),('OPERATIONS','field.submitKyc'),('OPERATIONS','field.approveKyc'),('OPERATIONS','platform.manage'),
 ('LEGAL','legal.viewContracts'),('LEGAL','legal.approveContract'),
 ('TECHNOLOGY','platform.manage'),('TECHNOLOGY','settings.manage')
)
insert into hq.role_permissions(role_id,permission_id)
select r.id,p.id from grants g join hq.roles r on r.code=g.role_code join hq.permissions p on p.code=g.permission_code
on conflict(role_id,permission_id) do update set effect='allow';

create or replace function public.hq_actor_authorization_v1(p_employee_id uuid) returns jsonb
language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare is_super boolean; permission_codes text[]; platform_ids uuid[]; platform_slugs text[];
begin
 if not exists(select 1 from hq.employees where id=p_employee_id and status='active') then raise exception 'HQ_ACTOR_INACTIVE';end if;
 select exists(select 1 from hq.employee_roles er join hq.roles r on r.id=er.role_id where er.employee_id=p_employee_id and r.code='SUPER_ADMIN' and r.active and er.revoked_at is null and (er.valid_until is null or er.valid_until>now())) into is_super;
 select coalesce(array_agg(code order by code),'{}'::text[]) into permission_codes from(
  select p.code from hq.permissions p where is_super
  union
  select p.code from hq.employee_roles er join hq.roles r on r.id=er.role_id and r.active join hq.role_permissions rp on rp.role_id=r.id and rp.effect='allow' join hq.permissions p on p.id=rp.permission_id where er.employee_id=p_employee_id and er.revoked_at is null and (er.valid_until is null or er.valid_until>now())
  union
  select o.permission_code from hq.employee_permission_overrides o where o.employee_id=p_employee_id and o.allowed
  except
  select o.permission_code from hq.employee_permission_overrides o where o.employee_id=p_employee_id and not o.allowed and not is_super
 )q;
 if is_super then select coalesce(array_agg(id order by slug),'{}'::uuid[]),coalesce(array_agg(slug order by slug),'{}'::text[]) into platform_ids,platform_slugs from hq.platforms where status='active';
 else select coalesce(array_agg(p.id order by p.slug),'{}'::uuid[]),coalesce(array_agg(p.slug order by p.slug),'{}'::text[]) into platform_ids,platform_slugs from hq.employee_platforms ep join hq.platforms p on p.id=ep.platform_id and p.status='active' where ep.employee_id=p_employee_id and ep.revoked_at is null and (ep.valid_until is null or ep.valid_until>now());end if;
 return jsonb_build_object('is_super_admin',is_super,'permissions',permission_codes,'platform_ids',platform_ids,'platform_slugs',platform_slugs);
end $$;

revoke all on function public.hq_actor_authorization_v1(uuid) from public,anon,authenticated;
grant execute on function public.hq_actor_authorization_v1(uuid) to service_role;
commit;
