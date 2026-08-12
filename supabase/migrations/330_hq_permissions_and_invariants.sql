begin;
insert into hq.permissions (code, module, action, data_class, description) values
  ('platforms.view','platforms','view','internal','Consultar plataformas autorizadas'),
  ('people.view','people','view','personal','Consultar directório corporativo'),
  ('people.manage','people','manage','personal','Gerir trabalhadores'),
  ('roles.manage','security','manage','restricted','Gerir roles e permissões'),
  ('security.super_admin','security','manage','restricted','Administração global exclusiva'),
  ('finance.view','finance','view','financial','Consultar informação financeira'),
  ('finance.budget.create','finance','create','financial','Criar orçamentos'),
  ('finance.expense.create','finance','create','financial','Criar despesas'),
  ('finance.transactions.review','finance','review','financial','Rever transacções'),
  ('finance.transactions.approve','finance','approve','financial','Aprovar transacções'),
  ('payment.execute','finance','execute','financial','Executar pagamentos'),
  ('payment.reconcile','accounting','reconcile','financial','Reconciliar pagamentos'),
  ('accounting.view','accounting','view','financial','Consultar contabilidade'),
  ('finance.result.prepare','accounting','prepare','financial','Preparar resultado'),
  ('profit_distribution.review','finance','review','financial','Rever distribuição'),
  ('reserved_matters.approve','governance','approve','restricted','Aprovar matérias reservadas'),
  ('ownership.view','governance','view','legal','Consultar ownership'),
  ('ownership.manage','governance','manage','restricted','Alterar ownership com resolução'),
  ('operations.view','operations','view','internal','Consultar operações'),
  ('tasks.assign','operations','assign','internal','Distribuir tarefas'),
  ('field.view','field','view','internal','Consultar Field'),
  ('field.manage','field','manage','internal','Gerir Field'),
  ('support.view','support','view','personal','Consultar apoio ao cliente'),
  ('support.manage','support','manage','personal','Gerir apoio ao cliente'),
  ('marketing.view','marketing','view','internal','Consultar marketing'),
  ('marketing.manage','marketing','manage','internal','Gerir marketing'),
  ('marketing.publish','marketing','publish','internal','Publicar campanhas'),
  ('acquisition.view','acquisition','view','internal','Consultar aquisição'),
  ('acquisition.manage','acquisition','manage','internal','Gerir aquisição'),
  ('ambassadors.view','ambassadors','view','internal','Consultar embaixadores'),
  ('ambassadors.manage','ambassadors','manage','internal','Gerir embaixadores'),
  ('hr.view','hr','view','personal','Consultar RH'),
  ('hr.manage','hr','manage','personal','Gerir RH'),
  ('payroll.view','hr','view','financial','Consultar payroll'),
  ('legal.view','legal','view','legal','Consultar Jurídico'),
  ('legal.manage','legal','manage','legal','Gerir processos jurídicos'),
  ('documents.restricted.view','documents','view','restricted','Consultar documentos restritos'),
  ('reports.view','reports','view','internal','Consultar relatórios'),
  ('reports.export','reports','export','confidential','Exportar relatórios'),
  ('audit.view','audit','view','restricted','Consultar auditoria'),
  ('technology.view','technology','view','internal','Consultar tecnologia'),
  ('technology.manage','technology','manage','restricted','Gerir integrações técnicas'),
  ('procurement.view','procurement','view','internal','Consultar compras'),
  ('procurement.manage','procurement','manage','financial','Gerir compras'),
  ('assets.view','assets','view','internal','Consultar património'),
  ('assets.manage','assets','manage','internal','Gerir património')
on conflict (code) do update set module=excluded.module, action=excluded.action, data_class=excluded.data_class, description=excluded.description;
insert into hq.role_permissions (role_id, permission_id)
select '50000000-0000-0000-0000-000000000001', id from hq.permissions
on conflict (role_id, permission_id) do nothing;
insert into hq.role_permissions (role_id, permission_id)
select '50000000-0000-0000-0000-000000000002', id from hq.permissions where code = any(array[
  'platforms.view','finance.view','finance.budget.create','finance.expense.create','finance.transactions.review',
  'finance.transactions.approve','accounting.view','profit_distribution.review','reserved_matters.approve',
  'ownership.view','payroll.view','reports.view','reports.export'
]) on conflict (role_id, permission_id) do nothing;
insert into hq.role_permissions (role_id, permission_id)
select '50000000-0000-0000-0000-000000000003', id from hq.permissions where code = any(array[
  'platforms.view','people.view','operations.view','tasks.assign','field.view','field.manage','support.view',
  'support.manage','marketing.view','acquisition.view','acquisition.manage','ambassadors.view','reports.view'
]) on conflict (role_id, permission_id) do nothing;
insert into hq.role_permissions (role_id, permission_id)
select '50000000-0000-0000-0000-000000000004', id from hq.permissions where code = any(array[
  'finance.view','accounting.view','finance.result.prepare','payment.reconcile','reports.view','reports.export'
]) on conflict (role_id, permission_id) do nothing;
insert into hq.role_permissions (role_id, permission_id)
select '50000000-0000-0000-0000-000000000005', id from hq.permissions where code = any(array[
  'people.view','hr.view','hr.manage','payroll.view','reports.view'
]) on conflict (role_id, permission_id) do nothing;
insert into hq.role_permissions (role_id, permission_id)
select '50000000-0000-0000-0000-000000000006', id from hq.permissions where code = any(array[
  'legal.view','legal.manage','documents.restricted.view','ownership.view','reports.view'
]) on conflict (role_id, permission_id) do nothing;
insert into hq.employee_platforms (employee_id, platform_id, granted_by)
select employees.employee_id, platforms.id, '40000000-0000-0000-0000-000000000001'::uuid
from (values
  ('40000000-0000-0000-0000-000000000001'::uuid),
  ('40000000-0000-0000-0000-000000000002'::uuid),
  ('40000000-0000-0000-0000-000000000003'::uuid)
) employees(employee_id) cross join hq.platforms as platforms
on conflict (employee_id, platform_id) do nothing;
create or replace function hq.enforce_single_super_admin() returns trigger
language plpgsql security definer set search_path = hq, pg_temp as $$
declare super_role uuid;
begin
  select id into super_role from hq.roles where code='SUPER_ADMIN' and legal_entity_id=(select legal_entity_id from hq.employees where id=new.employee_id);
  if new.role_id=super_role and new.revoked_at is null and (new.valid_until is null or new.valid_until > now()) and exists (
    select 1 from hq.employee_roles er where er.role_id=super_role and er.employee_id<>new.employee_id
      and er.revoked_at is null and (er.valid_until is null or er.valid_until > now())
  ) then raise exception 'HQ_SINGLE_SUPER_ADMIN_REQUIRED'; end if;
  return new;
end $$;
drop trigger if exists enforce_single_super_admin on hq.employee_roles;
create trigger enforce_single_super_admin before insert or update on hq.employee_roles
for each row execute function hq.enforce_single_super_admin();
create or replace function hq.enforce_ownership_total() returns trigger
language plpgsql security definer set search_path = hq, pg_temp as $$
declare ownership_total numeric;
begin
  select coalesce(sum(quota_percent),0) into ownership_total from hq.shareholders
  where legal_entity_id=new.legal_entity_id and effective_until is null and id<>new.id;
  if new.effective_until is null and ownership_total + new.quota_percent > 100 then
    raise exception 'HQ_OWNERSHIP_EXCEEDS_100_PERCENT';
  end if;
  return new;
end $$;
drop trigger if exists enforce_ownership_total on hq.shareholders;
create trigger enforce_ownership_total before insert or update on hq.shareholders
for each row execute function hq.enforce_ownership_total();
create or replace function hq.enforce_approval_separation() returns trigger
language plpgsql security definer set search_path = hq, pg_temp as $$
declare requester uuid;
begin
  select requested_by into requester from hq.approval_requests where id=new.request_id;
  if requester=new.approver_id then raise exception 'HQ_REQUESTER_CANNOT_APPROVE_OWN_REQUEST'; end if;
  return new;
end $$;
drop trigger if exists enforce_approval_separation on hq.approval_decisions;
create trigger enforce_approval_separation before insert or update on hq.approval_decisions
for each row execute function hq.enforce_approval_separation();
revoke all on all functions in schema hq from public, anon, authenticated;
grant execute on all functions in schema hq to service_role;
commit;
