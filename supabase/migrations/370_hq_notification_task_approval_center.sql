begin;

alter table hq.notifications
  add column if not exists origin_department_id uuid references hq.departments(id),
  add column if not exists priority text not null default 'normal',
  add column if not exists responsible_employee_id uuid references hq.employees(id),
  add column if not exists source_type text,
  add column if not exists source_id text,
  add column if not exists dedupe_key text;
do $$ begin
  if not exists(select 1 from pg_constraint where conname='notifications_priority_check' and conrelid='hq.notifications'::regclass) then
    alter table hq.notifications add constraint notifications_priority_check check(priority in('low','normal','high','urgent','critical'));
  end if;
end $$;
create unique index if not exists uq_hq_notification_dedupe on hq.notifications(employee_id,dedupe_key) where dedupe_key is not null;
create index if not exists idx_hq_notification_center on hq.notifications(employee_id,read_at,priority,created_at desc);

alter table hq.approval_requests
  add column if not exists priority text not null default 'normal',
  add column if not exists approval_rule_id uuid,
  add column if not exists approval_level integer not null default 1;

create table if not exists hq.approval_rules(
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  request_type text not null, label text not null, amount_min numeric(18,2), amount_max numeric(18,2), currency text not null default 'MZN',
  approver_department_id uuid not null references hq.departments(id), approver_role_code text,
  sequence_order integer not null default 1, required_approvals integer not null default 1 check(required_approvals>0),
  priority text not null default 'normal' check(priority in('low','normal','high','urgent','critical')),
  active boolean not null default true, metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_by uuid references hq.employees(id), updated_at timestamptz not null default now(),
  check(amount_min is null or amount_min>=0),check(amount_max is null or amount_min is null or amount_max>=amount_min),
  unique(legal_entity_id,request_type,sequence_order,amount_min,amount_max)
);
alter table hq.approval_requests drop constraint if exists approval_requests_approval_rule_id_fkey;
alter table hq.approval_requests add constraint approval_requests_approval_rule_id_fkey foreign key(approval_rule_id) references hq.approval_rules(id);

insert into hq.approval_rules(legal_entity_id,request_type,label,amount_min,amount_max,approver_department_id,approver_role_code,sequence_order,priority) values
('10000000-0000-0000-0000-000000000001','purchase','Até 10.000 MZN · Supervisor',0,10000,hq.workflow_department('OPERATIONS'),'SUPERVISOR',1,'normal'),
('10000000-0000-0000-0000-000000000001','purchase','10.001 a 100.000 MZN · Finanças',10000.01,100000,hq.workflow_department('FINANCE'),'FINANCE',2,'high'),
('10000000-0000-0000-0000-000000000001','purchase','Acima de 100.000 MZN · Direção',100000.01,null,hq.workflow_department('EXECUTIVE'),'SUPER_ADMIN',3,'urgent'),
('10000000-0000-0000-0000-000000000001','payment','Até 10.000 MZN · Supervisor',0,10000,hq.workflow_department('OPERATIONS'),'SUPERVISOR',1,'normal'),
('10000000-0000-0000-0000-000000000001','payment','10.001 a 100.000 MZN · Finanças',10000.01,100000,hq.workflow_department('FINANCE'),'FINANCE',2,'high'),
('10000000-0000-0000-0000-000000000001','payment','Acima de 100.000 MZN · Direção',100000.01,null,hq.workflow_department('EXECUTIVE'),'SUPER_ADMIN',3,'urgent'),
('10000000-0000-0000-0000-000000000001','expense','Despesa · regra financeira',0,null,hq.workflow_department('FINANCE'),'FINANCE',1,'high'),
('10000000-0000-0000-0000-000000000001','hiring','Contratação · Direção Executiva',null,null,hq.workflow_department('EXECUTIVE'),'SUPER_ADMIN',1,'high'),
('10000000-0000-0000-0000-000000000001','salary_change','Alteração salarial · Direção Executiva',null,null,hq.workflow_department('EXECUTIVE'),'SUPER_ADMIN',1,'urgent'),
('10000000-0000-0000-0000-000000000001','leave','Férias · Recursos Humanos',null,null,hq.workflow_department('HR'),'HUMAN_RESOURCES',1,'normal'),
('10000000-0000-0000-0000-000000000001','contract','Contrato · Jurídico',null,null,hq.workflow_department('LEGAL'),'LEGAL',1,'high'),
('10000000-0000-0000-0000-000000000001','campaign','Campanha · Marketing',null,null,hq.workflow_department('MARKETING'),'MARKETING',1,'normal'),
('10000000-0000-0000-0000-000000000001','marketing_publication','Publicação · Marketing',null,null,hq.workflow_department('MARKETING'),'MARKETING',1,'normal'),
('10000000-0000-0000-0000-000000000001','partner','Parceiro · Direção Executiva',null,null,hq.workflow_department('EXECUTIVE'),'SUPER_ADMIN',1,'high'),
('10000000-0000-0000-0000-000000000001','kyc','KYC · Conformidade',null,null,hq.workflow_department('COMPLIANCE'),'COMPLIANCE',1,'high'),
('10000000-0000-0000-0000-000000000001','profit_distribution','Distribuição de lucros · Direção',null,null,hq.workflow_department('EXECUTIVE'),'SUPER_ADMIN',1,'urgent'),
('10000000-0000-0000-0000-000000000001','special_access','Acesso especial · Tecnologia',null,null,hq.workflow_department('TECHNOLOGY'),'TECHNOLOGY',1,'critical'),
('10000000-0000-0000-0000-000000000001','critical_change','Alteração crítica · Direção',null,null,hq.workflow_department('EXECUTIVE'),'SUPER_ADMIN',1,'critical')
on conflict do nothing;
insert into hq.approval_type_permissions(request_type,permission_code,description) values
 ('hiring','approval.hiring.decide','Contratação'),('salary_change','approval.salary.decide','Alteração salarial'),
 ('profit_distribution','approval.profit.decide','Distribuição de lucros'),('special_access','approval.access.decide','Acesso especial')
on conflict do nothing;
insert into hq.permissions(code,module,action,data_class,description)
select distinct permission_code,'approvals','decide','restricted',description from hq.approval_type_permissions on conflict(code) do nothing;

create or replace function hq.apply_approval_rule() returns trigger language plpgsql security definer set search_path=hq,public as $$
declare r hq.approval_rules%rowtype;
begin
  select * into r from hq.approval_rules where legal_entity_id=new.legal_entity_id and request_type=new.request_type and active
    and (amount_min is null or coalesce(new.amount,0)>=amount_min) and (amount_max is null or coalesce(new.amount,0)<=amount_max)
    order by case when new.amount is null and amount_min is null then 0 else 1 end,sequence_order limit 1;
  if found then new.approval_rule_id:=r.id;new.department_id:=r.approver_department_id;new.required_approvals:=r.required_approvals;new.approval_level:=r.sequence_order;new.priority:=r.priority;end if;
  return new;
end $$;
drop trigger if exists trg_hq_apply_approval_rule on hq.approval_requests;
create trigger trg_hq_apply_approval_rule before insert on hq.approval_requests for each row execute function hq.apply_approval_rule();

create or replace function hq.sync_purchase_approval_policy() returns trigger language plpgsql security definer set search_path=hq,public as $$
begin
 if new.request_type='purchase' and new.amount_min is not null and new.approver_department_id=hq.workflow_department('EXECUTIVE') then
  update hq.workflow_policies set numeric_value=new.amount_min,updated_by=new.updated_by,updated_at=now() where policy_key='purchase_executive_approval_threshold_mzn';
 end if;return new;
end $$;
drop trigger if exists trg_sync_purchase_approval_policy on hq.approval_rules;
create trigger trg_sync_purchase_approval_policy after update on hq.approval_rules for each row execute function hq.sync_purchase_approval_policy();

create or replace function hq.notify_assignment_event() returns trigger language plpgsql security definer set search_path=hq,public as $$
declare recipient uuid;origin uuid;title_text text;body_text text;url_text text;source_kind text;priority_text text:='normal';platform_value uuid;key_text text;
begin
 if tg_table_name='tasks' and new.status in('completed','cancelled') then return new;end if;
 if tg_table_name='approval_requests' and new.status not in('submitted','under_review') then return new;end if;
 if tg_table_name='internal_requests' and new.status in('closed','archived') then return new;end if;
 if tg_table_name='support_tickets' and new.status in('resolved','closed') then return new;end if;
 if tg_table_name='workforce_requests' and new.status in('completed','cancelled','rejected') then return new;end if;
 if tg_table_name='tasks' then recipient:=new.assigned_to;origin:=new.department_id;title_text:='Nova tarefa atribuída';body_text:=new.title;url_text:='/minhas-tarefas';source_kind:='task';priority_text:=new.priority;platform_value:=new.platform_id;
 elsif tg_table_name='approval_requests' then title_text:='Pedido aguardando aprovação';body_text:=new.title;url_text:='/aprovacoes';source_kind:='approval';priority_text:=new.priority;platform_value:=new.platform_id;
 elsif tg_table_name='internal_requests' then recipient:=coalesce(new.assigned_to,new.requester_id);origin:=new.target_department_id;title_text:=case when new.status='resolved' then 'Pedido interno respondido' else 'Pedido interno atualizado' end;body_text:=new.subject;url_text:='/apoio-interno';source_kind:='internal_request';priority_text:=new.priority;
 elsif tg_table_name='support_tickets' then recipient:=new.assigned_to;origin:=new.current_department_id;title_text:='Ticket encaminhado';body_text:=coalesce(new.ticket_number||' · ','')||new.subject;url_text:='/apoio-cliente';source_kind:='support_ticket';priority_text:=new.priority;platform_value:=new.platform_id;
 elsif tg_table_name='workforce_requests' then origin:=hq.workflow_department('HR');title_text:=case when new.request_type='hiring' then 'Trabalhador em processo de admissão' else 'Trabalhador em processo de desligamento' end;body_text:=coalesce(new.candidate_name,new.reason);url_text:='/recursos-humanos';source_kind:='workforce_request';priority_text:='high';platform_value:=new.platform_id;
 elsif tg_table_name='field_kyc_cases' then origin:=hq.workflow_department('FIELD');title_text:='Documento KYC enviado';body_text:='Novo processo KYC para revisão';url_text:='/field';source_kind:='field_kyc_case';priority_text:='high';platform_value:=new.platform_id;
 elsif tg_table_name='compliance_risks' then recipient:=new.owner_employee_id;origin:=hq.workflow_department('COMPLIANCE');title_text:='Risco crítico identificado';body_text:=new.title;url_text:='/conformidade-risco';source_kind:='compliance_risk';priority_text:=case when new.risk_score>=20 then 'critical' else 'high' end;platform_value:=new.platform_id;
 elsif tg_table_name='technology_incidents' then recipient:=new.owner_employee_id;origin:=hq.workflow_department('TECHNOLOGY');title_text:='Incidente técnico aberto';body_text:=new.title;url_text:='/tecnologia';source_kind:='technology_incident';priority_text:=case when new.severity='sev1' then 'critical' when new.severity='sev2' then 'urgent' else 'high' end;platform_value:=new.platform_id;
 elsif tg_table_name='marketing_campaigns' then recipient:=new.owner_id;origin:=hq.workflow_department('MARKETING');title_text:='Campanha aguardando aprovação';body_text:=new.title;url_text:='/marketing';source_kind:='campaign';priority_text:='normal';
 else return new;end if;
 key_text:=source_kind||':'||new.id::text||':'||coalesce(new.status,'created');
 if tg_table_name='approval_requests' then
   insert into hq.notifications(employee_id,type,title,body,platform_id,target_url,origin_department_id,priority,responsible_employee_id,source_type,source_id,dedupe_key)
   select e.id,'approval_required',title_text,body_text,platform_value,url_text,new.department_id,priority_text,e.id,source_kind,new.id::text,key_text from hq.employees e where e.department_id=new.department_id and e.status='active' on conflict(employee_id,dedupe_key) where dedupe_key is not null do nothing;
 elsif recipient is not null then
   insert into hq.notifications(employee_id,type,title,body,platform_id,target_url,origin_department_id,priority,responsible_employee_id,source_type,source_id,dedupe_key)
   values(recipient,source_kind,title_text,body_text,platform_value,url_text,origin,priority_text,recipient,source_kind,new.id::text,key_text) on conflict(employee_id,dedupe_key) where dedupe_key is not null do nothing;
 else
   insert into hq.notifications(employee_id,type,title,body,platform_id,target_url,origin_department_id,priority,responsible_employee_id,source_type,source_id,dedupe_key)
   select e.id,source_kind,title_text,body_text,platform_value,url_text,origin,priority_text,e.id,source_kind,new.id::text,key_text from hq.employees e where e.department_id=origin and e.status='active' on conflict(employee_id,dedupe_key) where dedupe_key is not null do nothing;
 end if;return new;
end $$;

do $$ declare t text;begin foreach t in array array['tasks','approval_requests','internal_requests','support_tickets','workforce_requests','field_kyc_cases','compliance_risks','technology_incidents','marketing_campaigns'] loop
 execute format('drop trigger if exists trg_hq_notify_assignment on hq.%I',t);execute format('create trigger trg_hq_notify_assignment after insert or update on hq.%I for each row execute function hq.notify_assignment_event()',t);end loop;end $$;

create or replace function public.hq_refresh_due_notifications_v1(p_employee_id uuid) returns integer language plpgsql security definer set search_path=hq,public as $$
declare employee_department uuid;created_count integer:=0;n integer;
begin
 select department_id into employee_department from hq.employees where id=p_employee_id and status='active';if employee_department is null then return 0;end if;
 insert into hq.notifications(employee_id,type,title,body,platform_id,target_url,origin_department_id,priority,responsible_employee_id,source_type,source_id,dedupe_key)
 select p_employee_id,'deadline','Projeto ou tarefa atrasada',t.title,t.platform_id,'/projectos-tarefas',t.department_id,'urgent',p_employee_id,'task',t.id::text,'task-overdue:'||t.id from hq.tasks t where t.assigned_to=p_employee_id and t.status not in('completed','cancelled') and t.due_at<now() on conflict(employee_id,dedupe_key) where dedupe_key is not null do nothing;get diagnostics n=row_count;created_count:=created_count+n;
 insert into hq.notifications(employee_id,type,title,body,platform_id,target_url,origin_department_id,priority,responsible_employee_id,source_type,source_id,dedupe_key)
 select p_employee_id,'payment_due','Pagamento pendente',p.description,p.platform_id,'/financas',hq.workflow_department('FINANCE'),case when p.due_at<now() then 'urgent' else 'high' end,p_employee_id,'payment_request',p.id::text,'payment-pending:'||p.id from hq.payment_requests p where employee_department=hq.workflow_department('FINANCE') and p.status in('pending','approved') and (p.due_at is null or p.due_at<=now()+interval '7 days') on conflict(employee_id,dedupe_key) where dedupe_key is not null do nothing;get diagnostics n=row_count;created_count:=created_count+n;
 insert into hq.notifications(employee_id,type,title,body,target_url,origin_department_id,priority,responsible_employee_id,source_type,source_id,dedupe_key)
 select p_employee_id,'contract_expiry','Contrato próximo do vencimento',c.title,'/juridico',hq.workflow_department('LEGAL'),'high',p_employee_id,'contract',c.id::text,'contract-expiry:'||c.id from hq.contracts c where employee_department=hq.workflow_department('LEGAL') and c.status in('signed','active') and c.expires_on between current_date and current_date+30 on conflict(employee_id,dedupe_key) where dedupe_key is not null do nothing;get diagnostics n=row_count;created_count:=created_count+n;
 insert into hq.notifications(employee_id,type,title,body,target_url,origin_department_id,priority,responsible_employee_id,source_type,source_id,dedupe_key)
 select p_employee_id,'asset_overdue','Equipamento não devolvido',a.name,'/patrimonio',hq.workflow_department('ASSETS'),'urgent',p_employee_id,'asset_assignment',aa.id::text,'asset-overdue:'||aa.id from hq.asset_assignments aa join hq.assets a on a.id=aa.asset_id where employee_department=hq.workflow_department('ASSETS') and aa.status='active' and aa.expected_return_at<now() on conflict(employee_id,dedupe_key) where dedupe_key is not null do nothing;get diagnostics n=row_count;created_count:=created_count+n;
 return created_count;
end $$;

alter table hq.approval_rules enable row level security;revoke all on hq.approval_rules from public,anon,authenticated;grant all on hq.approval_rules to service_role;
revoke all on function public.hq_refresh_due_notifications_v1(uuid) from public,anon,authenticated;grant execute on function public.hq_refresh_due_notifications_v1(uuid) to service_role;
create index if not exists idx_hq_approval_rules_lookup on hq.approval_rules(legal_entity_id,request_type,active,amount_min,amount_max);
commit;
