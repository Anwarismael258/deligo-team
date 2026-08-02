begin;

-- Extends the central workflow engine without replacing any operational table.
alter table hq.workflow_cases drop constraint if exists workflow_cases_case_type_check;
alter table hq.workflow_cases add constraint workflow_cases_case_type_check
  check(case_type in('partner_onboarding','support_case','incident','internal_request','purchase','hiring','offboarding','technical_incident'));
alter table hq.workflow_steps add column if not exists decided_by uuid references hq.employees(id);

alter table hq.purchase_requests add column if not exists workflow_case_id uuid references hq.workflow_cases(id);
create unique index if not exists uq_purchase_workflow_case on hq.purchase_requests(workflow_case_id) where workflow_case_id is not null;
alter table hq.technology_incidents add column if not exists workflow_case_id uuid references hq.workflow_cases(id);
create unique index if not exists uq_technology_incident_workflow_case on hq.technology_incidents(workflow_case_id) where workflow_case_id is not null;

create table if not exists hq.workflow_policies(
  policy_key text primary key, numeric_value numeric(18,2), text_value text,
  updated_by uuid references hq.employees(id), updated_at timestamptz not null default now()
);
insert into hq.workflow_policies(policy_key,numeric_value,text_value)
values('purchase_executive_approval_threshold_mzn',100000,'Compras iguais ou superiores ao limite exigem aprovação da Direção')
on conflict(policy_key) do nothing;

create table if not exists hq.workforce_requests(
  id uuid primary key default gen_random_uuid(), request_number bigint generated always as identity,
  legal_entity_id uuid not null references hq.legal_entities(id), platform_id uuid references hq.platforms(id),
  request_type text not null check(request_type in('hiring','offboarding')),
  employee_id uuid references hq.employees(id), candidate_name text, candidate_phone text,
  job_title text, department_id uuid references hq.departments(id), requested_role_code text,
  proposed_salary numeric(18,2), currency text not null default 'MZN', reason text not null,
  requested_by uuid not null references hq.employees(id), workflow_case_id uuid unique references hq.workflow_cases(id),
  status text not null default 'submitted' check(status in('submitted','in_progress','waiting_approval','approved','rejected','completed','cancelled')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check((request_type='hiring' and candidate_name is not null and job_title is not null and department_id is not null) or (request_type='offboarding' and employee_id is not null))
);

create or replace function hq.workflow_department(p_code text) returns uuid
language sql stable security definer set search_path=hq,public as $$
  select id from hq.departments where legal_entity_id='10000000-0000-0000-0000-000000000001' and code=p_code limit 1
$$;

create or replace function hq.notify_department(p_department uuid,p_type text,p_title text,p_body text,p_platform uuid,p_url text) returns void
language sql security definer set search_path=hq,public as $$
  insert into hq.notifications(employee_id,type,title,body,platform_id,target_url)
  select id,p_type,p_title,p_body,p_platform,p_url from hq.employees where department_id=p_department and status='active'
$$;

create or replace function public.hq_start_purchase_workflow_v1(p_purchase_request_id uuid,p_actor_employee_id uuid) returns jsonb
language plpgsql security definer set search_path=hq,public as $$
declare pr hq.purchase_requests%rowtype;c hq.workflow_cases%rowtype;threshold numeric;origin uuid;manager uuid;needs_exec boolean;
begin
  select * into pr from hq.purchase_requests where id=p_purchase_request_id for update;if not found then raise exception 'Pedido inexistente';end if;
  if pr.workflow_case_id is not null then select * into c from hq.workflow_cases where id=pr.workflow_case_id;return to_jsonb(c);end if;
  select coalesce(numeric_value,100000) into threshold from hq.workflow_policies where policy_key='purchase_executive_approval_threshold_mzn';
  origin:=pr.department_id;select manager_id into manager from hq.employees where id=pr.requested_by;needs_exec:=pr.estimated_amount>=threshold;
  insert into hq.workflow_cases(legal_entity_id,platform_id,origin_department_id,current_department_id,case_type,title,source_type,source_id,created_by,assigned_to,status)
  values(pr.legal_entity_id,pr.platform_id,origin,origin,'purchase','Pedido PR-'||pr.request_number||': '||pr.justification,'purchase_request',pr.id::text,p_actor_employee_id,manager,'in_progress') returning * into c;
  update hq.purchase_requests set workflow_case_id=c.id where id=pr.id;
  insert into hq.workflow_steps(case_id,step_order,department_id,step_type,target_type,target_id,assigned_to,status,started_at) values
    (c.id,1,origin,'supervisor_approval','purchase_request',pr.id::text,manager,'pending',now()),
    (c.id,2,hq.workflow_department('FINANCE'),'budget_validation','purchase_request',pr.id::text,null,'blocked',null),
    (c.id,3,hq.workflow_department('PROCUREMENT'),'procurement_execution','purchase_request',pr.id::text,null,'blocked',null),
    (c.id,4,hq.workflow_department('EXECUTIVE'),'purchase_executive_approval','purchase_request',pr.id::text,null,case when needs_exec then 'blocked' else 'completed' end,case when needs_exec then null else now() end),
    (c.id,5,hq.workflow_department('ASSETS'),'asset_registration','purchase_request',pr.id::text,null,'blocked',null),
    (c.id,6,hq.workflow_department('ACCOUNTING'),'purchase_accounting','purchase_request',pr.id::text,null,'blocked',null),
    (c.id,7,hq.workflow_department('FINANCE'),'purchase_payment','purchase_request',pr.id::text,null,'blocked',null);
  insert into hq.workflow_links(case_id,resource_type,resource_id) values(c.id,'purchase_request',pr.id::text) on conflict do nothing;
  perform hq.notify_department(origin,'workflow_assigned',c.case_number||' requer supervisão',c.title,pr.platform_id,'/compras');
  insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,platform_id,module,target_type,target_id,result,correlation_id,metadata)
  values(p_actor_employee_id,'purchase_workflow_started',pr.legal_entity_id,pr.platform_id,'procurement','purchase_request',pr.id::text,'success',c.correlation_id,jsonb_build_object('case_number',c.case_number,'threshold',threshold,'executive_approval',needs_exec));
  return to_jsonb(c);
end $$;

create or replace function public.hq_start_workforce_workflow_v1(p_request_id uuid,p_actor_employee_id uuid) returns jsonb
language plpgsql security definer set search_path=hq,public as $$
declare r hq.workforce_requests%rowtype;c hq.workflow_cases%rowtype;origin uuid:=hq.workflow_department('HR');
begin
 select * into r from hq.workforce_requests where id=p_request_id for update;if not found then raise exception 'Pedido inexistente';end if;
 if r.workflow_case_id is not null then select * into c from hq.workflow_cases where id=r.workflow_case_id;return to_jsonb(c);end if;
 insert into hq.workflow_cases(legal_entity_id,platform_id,origin_department_id,current_department_id,case_type,title,source_type,source_id,created_by,status)
 values(r.legal_entity_id,r.platform_id,origin,origin,r.request_type,case when r.request_type='hiring' then 'Contratação: '||r.candidate_name else 'Desligamento: '||(select display_name from hq.employees where id=r.employee_id) end,'workforce_request',r.id::text,p_actor_employee_id,'in_progress') returning * into c;
 update hq.workforce_requests set workflow_case_id=c.id,status='in_progress',updated_at=now() where id=r.id;
 if r.request_type='hiring' then
  insert into hq.workflow_steps(case_id,step_order,department_id,step_type,target_type,target_id,status,started_at) values
   (c.id,1,origin,'hr_candidate_selection','workforce_request',r.id::text,'pending',now()),(c.id,2,hq.workflow_department('LEGAL'),'employment_contract_review','workforce_request',r.id::text,'blocked',null),
   (c.id,3,hq.workflow_department('EXECUTIVE'),'hiring_executive_approval','workforce_request',r.id::text,'blocked',null),(c.id,4,origin,'hr_employee_creation','workforce_request',r.id::text,'blocked',null),
   (c.id,5,origin,'people_account_creation','workforce_request',r.id::text,'blocked',null),(c.id,6,hq.workflow_department('TECHNOLOGY'),'technology_access_provision','workforce_request',r.id::text,'blocked',null),
   (c.id,7,hq.workflow_department('ASSETS'),'employee_asset_assignment','workforce_request',r.id::text,'blocked',null),(c.id,8,hq.workflow_department('FINANCE'),'payroll_finance_setup','workforce_request',r.id::text,'blocked',null),
   (c.id,9,hq.workflow_department('ACCOUNTING'),'payroll_accounting_setup','workforce_request',r.id::text,'blocked',null);
 else
  insert into hq.workflow_steps(case_id,step_order,department_id,step_type,target_type,target_id,status,started_at) values
   (c.id,1,origin,'hr_offboarding_start','workforce_request',r.id::text,'pending',now()),(c.id,2,hq.workflow_department('TECHNOLOGY'),'technology_access_revoke','workforce_request',r.id::text,'blocked',null),
   (c.id,3,origin,'people_account_suspend','workforce_request',r.id::text,'blocked',null),(c.id,4,hq.workflow_department('ASSETS'),'employee_assets_return','workforce_request',r.id::text,'blocked',null),
   (c.id,5,hq.workflow_department('FINANCE'),'offboarding_finance_close','workforce_request',r.id::text,'blocked',null),(c.id,6,hq.workflow_department('ACCOUNTING'),'offboarding_accounting_close','workforce_request',r.id::text,'blocked',null),
   (c.id,7,hq.workflow_department('LEGAL'),'exit_documents_validation','workforce_request',r.id::text,'blocked',null);
 end if;
 insert into hq.workflow_links(case_id,resource_type,resource_id) values(c.id,'workforce_request',r.id::text) on conflict do nothing;
 perform hq.notify_department(origin,'workflow_assigned',c.case_number||' iniciado',c.title,r.platform_id,'/recursos-humanos');
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,platform_id,module,target_type,target_id,result,correlation_id,metadata) values(p_actor_employee_id,r.request_type||'_workflow_started',r.legal_entity_id,r.platform_id,'hr','workforce_request',r.id::text,'success',c.correlation_id,jsonb_build_object('case_number',c.case_number));
 return to_jsonb(c);
end $$;

create or replace function public.hq_start_technical_incident_workflow_v1(p_incident_id uuid,p_actor_employee_id uuid) returns jsonb
language plpgsql security definer set search_path=hq,public as $$
declare i hq.technology_incidents%rowtype;c hq.workflow_cases%rowtype;tech uuid:=hq.workflow_department('TECHNOLOGY');d text;
begin
 select * into i from hq.technology_incidents where id=p_incident_id for update;if not found then raise exception 'Incidente inexistente';end if;
 if i.workflow_case_id is not null then select * into c from hq.workflow_cases where id=i.workflow_case_id;return to_jsonb(c);end if;
 insert into hq.workflow_cases(legal_entity_id,platform_id,origin_department_id,current_department_id,case_type,title,source_type,source_id,created_by,status)
 values(i.legal_entity_id,i.platform_id,tech,tech,'technical_incident',i.title,'technology_incident',i.id::text,p_actor_employee_id,'in_progress') returning * into c;
 update hq.technology_incidents set workflow_case_id=c.id where id=i.id;
 insert into hq.workflow_steps(case_id,step_order,department_id,step_type,target_type,target_id,status,started_at) values
  (c.id,1,tech,'technical_response','technology_incident',i.id::text,'pending',now()),(c.id,2,hq.workflow_department('SUPPORT'),'customer_communication','technology_incident',i.id::text,'pending',now()),
  (c.id,3,hq.workflow_department('OPERATIONS'),'operational_continuity','technology_incident',i.id::text,'pending',now()),(c.id,4,hq.workflow_department('COMPLIANCE'),'incident_risk_assessment','technology_incident',i.id::text,'pending',now()),
  (c.id,5,tech,'incident_resolution_report','technology_incident',i.id::text,'blocked',null);
 foreach d in array array['EXECUTIVE','SUPPORT','OPERATIONS','COMPLIANCE'] loop perform hq.notify_department(hq.workflow_department(d),'technical_incident',c.case_number||' · '||upper(i.severity),i.title,i.platform_id,case when d='EXECUTIVE' then '/' else '/tecnologia' end);end loop;
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,platform_id,module,target_type,target_id,result,correlation_id,metadata) values(p_actor_employee_id,'technical_incident_workflow_started',i.legal_entity_id,i.platform_id,'technology','technology_incident',i.id::text,'success',c.correlation_id,jsonb_build_object('case_number',c.case_number,'severity',i.severity));
 return to_jsonb(c);
end $$;

create or replace function public.hq_link_workforce_employee_v1(p_request_id uuid,p_employee_id uuid,p_actor_employee_id uuid) returns jsonb
language plpgsql security definer set search_path=hq,public as $$
declare r hq.workforce_requests%rowtype;
begin
 select * into r from hq.workforce_requests where id=p_request_id for update;if not found or r.request_type<>'hiring' then raise exception 'Contratacao inexistente';end if;
 if not exists(select 1 from hq.employees where id=p_employee_id) then raise exception 'Colaborador inexistente';end if;
 update hq.workforce_requests set employee_id=p_employee_id,updated_at=now() where id=r.id;
 insert into hq.workflow_links(case_id,resource_type,resource_id) values(r.workflow_case_id,'employee',p_employee_id::text) on conflict do nothing;
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,platform_id,module,target_type,target_id,result,metadata) values(p_actor_employee_id,'employee_linked_to_hiring',r.legal_entity_id,r.platform_id,'hr','workforce_request',r.id::text,'success',jsonb_build_object('employee_id',p_employee_id));
 return jsonb_build_object('request_id',r.id,'employee_id',p_employee_id);
end $$;

create or replace function public.hq_decide_workflow_step_v1(p_step_id uuid,p_actor_employee_id uuid,p_decision text,p_result text,p_allow_override boolean default false) returns jsonb
language plpgsql security definer set search_path=hq,public as $$
declare s hq.workflow_steps%rowtype;c hq.workflow_cases%rowtype;actor_department uuid;next_step hq.workflow_steps%rowtype;r hq.workforce_requests%rowtype;approval_id uuid;incident_status text;
begin
 if p_decision not in('completed','rejected') or coalesce(length(trim(p_result)),0)<3 then raise exception 'Decisao ou resultado invalido';end if;
 select * into s from hq.workflow_steps where id=p_step_id for update;if not found then raise exception 'Etapa inexistente';end if;
 select * into c from hq.workflow_cases where id=s.case_id for update;select department_id into actor_department from hq.employees where id=p_actor_employee_id and status='active';
 if not p_allow_override and actor_department is distinct from s.department_id and s.assigned_to is distinct from p_actor_employee_id then raise exception 'Etapa fora do departamento';end if;
 if s.status not in('pending','in_progress') then raise exception 'Etapa nao esta disponivel';end if;
 if s.step_type='budget_validation' and not exists(select 1 from hq.purchase_requests pr join hq.budgets b on b.id=pr.budget_id where pr.id=s.target_id::uuid and b.status='approved' and b.amount>=pr.estimated_amount) then raise exception 'Orcamento aprovado e suficiente obrigatorio';end if;
 if s.step_type='procurement_execution' and not exists(select 1 from hq.purchase_requests where id=s.target_id::uuid and status in('received','invoiced','paid')) then raise exception 'Encomenda e rececao obrigatorias';end if;
 if s.step_type='hr_employee_creation' then select * into r from hq.workforce_requests where id=s.target_id::uuid;if r.employee_id is null then raise exception 'Colaborador deve ser criado e associado';end if;end if;
 if s.step_type='employee_assets_return' then select * into r from hq.workforce_requests where id=s.target_id::uuid;if exists(select 1 from hq.asset_assignments where employee_id=r.employee_id and status='active') then raise exception 'Existem ativos por devolver';end if;end if;
 if s.step_type='incident_resolution_report' then select status into incident_status from hq.technology_incidents where id=s.target_id::uuid;if incident_status not in('resolved','closed') then raise exception 'Incidente deve estar resolvido';end if;end if;
 update hq.workflow_steps set status=p_decision,result=p_result,decided_by=p_actor_employee_id,completed_at=now(),updated_at=now() where id=s.id;
 if p_decision='rejected' then update hq.workflow_cases set status='rejected',updated_at=now() where id=c.id;update hq.workforce_requests set status='rejected',updated_at=now() where workflow_case_id=c.id;
 elsif c.case_type='partner_onboarding' then
   if s.step_type in('commercial_review','kyc_review') and not exists(select 1 from hq.workflow_steps where case_id=c.id and step_type in('commercial_review','kyc_review') and id<>s.id and status<>'completed') then update hq.workflow_steps set status='pending',started_at=now(),updated_at=now() where case_id=c.id and step_type='contract_review' and status='blocked';
   elsif s.step_type='contract_review' then
    update hq.workflow_steps set status='waiting_approval',started_at=now(),updated_at=now() where case_id=c.id and step_type='partner_approval';
    insert into hq.approval_requests(legal_entity_id,platform_id,department_id,request_type,target_type,target_id,title,status,required_approvals,requested_by,submitted_at,workflow_case_id)
    values(c.legal_entity_id,c.platform_id,hq.workflow_department('EXECUTIVE'),'partner','workflow_case',c.id::text,'Aprovar parceiro - '||c.case_number,'submitted',1,p_actor_employee_id,now(),c.id) returning id into approval_id;
    update hq.workflow_cases set status='waiting_approval',current_department_id=hq.workflow_department('EXECUTIVE'),updated_at=now() where id=c.id;
    perform hq.notify_department(hq.workflow_department('EXECUTIVE'),'approval_required','Aprovação '||c.case_number,c.title,c.platform_id,'/aprovacoes');
   end if;
 elsif c.case_type='technical_incident' then
   if s.step_type<>'incident_resolution_report' and not exists(select 1 from hq.workflow_steps where case_id=c.id and step_type in('technical_response','customer_communication','operational_continuity','incident_risk_assessment') and status<>'completed') then update hq.workflow_steps set status='pending',started_at=now(),updated_at=now() where case_id=c.id and step_type='incident_resolution_report';end if;
   if s.step_type='incident_resolution_report' then update hq.workflow_cases set status='completed',current_department_id=null,updated_at=now() where id=c.id;end if;
 else
   select * into next_step from hq.workflow_steps where case_id=c.id and step_order>s.step_order and status='blocked' order by step_order limit 1;
   if found then
    if next_step.step_type in('purchase_executive_approval','hiring_executive_approval') then
      update hq.workflow_steps set status='waiting_approval',started_at=now(),updated_at=now() where id=next_step.id;
      insert into hq.approval_requests(legal_entity_id,platform_id,department_id,request_type,target_type,target_id,title,status,required_approvals,requested_by,submitted_at,workflow_case_id)
      values(c.legal_entity_id,c.platform_id,next_step.department_id,case when c.case_type='purchase' then 'purchase' else 'hiring' end,'workflow_case',c.id::text,'Aprovar '||c.case_number||' · '||c.title,'submitted',1,p_actor_employee_id,now(),c.id) returning id into approval_id;
      update hq.workflow_cases set status='waiting_approval',current_department_id=next_step.department_id,updated_at=now() where id=c.id;
      perform hq.notify_department(next_step.department_id,'approval_required','Aprovação '||c.case_number,c.title,c.platform_id,'/aprovacoes');
    else update hq.workflow_steps set status='pending',started_at=now(),updated_at=now() where id=next_step.id;update hq.workflow_cases set status='in_progress',current_department_id=next_step.department_id,updated_at=now() where id=c.id;perform hq.notify_department(next_step.department_id,'workflow_assigned',c.case_number||' recebido',c.title,c.platform_id,'/');end if;
   else
    update hq.workflow_cases set status='completed',current_department_id=null,updated_at=now() where id=c.id;update hq.workforce_requests set status='completed',updated_at=now() where workflow_case_id=c.id;
    if c.case_type='offboarding' then select * into r from hq.workforce_requests where workflow_case_id=c.id;update hq.employees set status='offboarded',updated_at=now() where id=r.employee_id;end if;
   end if;
 end if;
 if s.step_type='people_account_suspend' then select * into r from hq.workforce_requests where id=s.target_id::uuid;update hq.employees set status='suspended',updated_at=now() where id=r.employee_id;end if;
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,platform_id,module,target_type,target_id,result,correlation_id,metadata) values(p_actor_employee_id,'workflow_step_'||p_decision,c.legal_entity_id,c.platform_id,'workflow','workflow_step',s.id::text,'success',c.correlation_id,jsonb_build_object('case_number',c.case_number,'step_type',s.step_type,'result',p_result,'approval_id',approval_id));
 return jsonb_build_object('case_id',c.id,'case_number',c.case_number,'step_id',s.id,'decision',p_decision,'approval_id',approval_id);
end $$;

create or replace function public.hq_apply_workflow_approval_v1(p_case_id uuid,p_actor_employee_id uuid,p_decision text,p_reason text default null) returns jsonb
language plpgsql security definer set search_path=hq,public as $$
declare c hq.workflow_cases%rowtype;s hq.workflow_steps%rowtype;next_step hq.workflow_steps%rowtype;
begin
 select * into c from hq.workflow_cases where id=p_case_id for update;if not found then raise exception 'Processo inexistente';end if;
 select * into s from hq.workflow_steps where case_id=c.id and status='waiting_approval' order by step_order limit 1 for update;if not found then raise exception 'Processo nao aguarda aprovacao';end if;
 update hq.workflow_steps set status=case when p_decision='approved' then 'completed' else 'rejected' end,result=coalesce(p_reason,case when p_decision='approved' then 'Aprovado' else 'Rejeitado' end),decided_by=p_actor_employee_id,completed_at=now(),updated_at=now() where id=s.id;
 if p_decision<>'approved' then update hq.workflow_cases set status='rejected',updated_at=now() where id=c.id;update hq.workforce_requests set status='rejected',updated_at=now() where workflow_case_id=c.id;
 else
  select * into next_step from hq.workflow_steps where case_id=c.id and step_order>s.step_order and status='blocked' order by step_order limit 1;
  if found then update hq.workflow_steps set status='pending',started_at=now(),updated_at=now() where id=next_step.id;update hq.workflow_cases set status='in_progress',current_department_id=next_step.department_id,updated_at=now() where id=c.id;perform hq.notify_department(next_step.department_id,'workflow_assigned',c.case_number||' aprovado',c.title,c.platform_id,'/');else update hq.workflow_cases set status='completed',current_department_id=null,updated_at=now() where id=c.id;end if;
 end if;
 return jsonb_build_object('case_id',c.id,'case_number',c.case_number,'decision',p_decision,'step_type',s.step_type);
end $$;

alter table hq.workflow_policies enable row level security;alter table hq.workforce_requests enable row level security;
revoke all on hq.workflow_policies,hq.workforce_requests from public,anon,authenticated;grant all on hq.workflow_policies,hq.workforce_requests to service_role;
grant all on all sequences in schema hq to service_role;
revoke all on function public.hq_start_purchase_workflow_v1(uuid,uuid),public.hq_start_workforce_workflow_v1(uuid,uuid),public.hq_start_technical_incident_workflow_v1(uuid,uuid),public.hq_link_workforce_employee_v1(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hq_start_purchase_workflow_v1(uuid,uuid),public.hq_start_workforce_workflow_v1(uuid,uuid),public.hq_start_technical_incident_workflow_v1(uuid,uuid),public.hq_link_workforce_employee_v1(uuid,uuid,uuid) to service_role;
create index if not exists idx_workforce_requests_status on hq.workforce_requests(request_type,status,created_at desc);
commit;
