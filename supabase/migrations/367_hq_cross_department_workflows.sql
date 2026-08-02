begin;

insert into hq.departments(id,legal_entity_id,code,name)
values('30000000-0000-0000-0000-000000000015','10000000-0000-0000-0000-000000000001','COMPLIANCE','Conformidade e Risco')
on conflict(legal_entity_id,code) do update set name=excluded.name;

create sequence if not exists hq.workflow_case_number_seq;
create sequence if not exists hq.support_ticket_number_seq;

create or replace function hq.next_workflow_case_number() returns text
language sql security definer set search_path=hq,public as $$
  select 'WF-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('hq.workflow_case_number_seq')::text,6,'0')
$$;
create or replace function hq.next_support_ticket_number() returns text
language sql security definer set search_path=hq,public as $$
  select 'SUP-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('hq.support_ticket_number_seq')::text,6,'0')
$$;

create table if not exists hq.workflow_cases(
  id uuid primary key default gen_random_uuid(),
  case_number text not null unique default hq.next_workflow_case_number(),
  legal_entity_id uuid not null references hq.legal_entities(id),
  platform_id uuid references hq.platforms(id),
  origin_department_id uuid not null references hq.departments(id),
  current_department_id uuid references hq.departments(id),
  case_type text not null check(case_type in('partner_onboarding','support_case','incident','internal_request')),
  title text not null, source_type text not null, source_id text not null,
  created_by uuid not null references hq.employees(id), assigned_to uuid references hq.employees(id),
  status text not null default 'open' check(status in('open','in_progress','waiting_approval','approved','rejected','completed','cancelled')),
  correlation_id uuid not null default gen_random_uuid(), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(source_type,source_id,case_type)
);
create table if not exists hq.workflow_steps(
  id uuid primary key default gen_random_uuid(), case_id uuid not null references hq.workflow_cases(id) on delete cascade,
  step_order integer not null, department_id uuid not null references hq.departments(id), step_type text not null,
  target_type text, target_id text, assigned_to uuid references hq.employees(id),
  status text not null default 'blocked' check(status in('blocked','pending','in_progress','waiting_approval','completed','rejected','cancelled')),
  result text, started_at timestamptz, completed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(case_id,step_order)
);
create table if not exists hq.workflow_links(
  id uuid primary key default gen_random_uuid(), case_id uuid not null references hq.workflow_cases(id) on delete cascade,
  resource_type text not null, resource_id text not null, created_at timestamptz not null default now(), unique(case_id,resource_type,resource_id)
);
create table if not exists hq.support_department_assignments(
  id uuid primary key default gen_random_uuid(), ticket_id uuid not null references hq.support_tickets(id) on delete cascade,
  department_id uuid not null references hq.departments(id), assigned_to uuid references hq.employees(id),
  assigned_by uuid references hq.employees(id), reason text not null,
  status text not null default 'pending' check(status in('pending','accepted','responded','completed','cancelled')),
  response text, created_at timestamptz not null default now(), responded_at timestamptz
);

alter table hq.field_visits
  add column if not exists legal_entity_id uuid references hq.legal_entities(id) default '10000000-0000-0000-0000-000000000001',
  add column if not exists department_id uuid references hq.departments(id) default '30000000-0000-0000-0000-000000000009',
  add column if not exists created_by uuid references hq.employees(id),
  add column if not exists workflow_case_id uuid references hq.workflow_cases(id);
alter table hq.field_kyc_cases add column if not exists workflow_case_id uuid references hq.workflow_cases(id);
alter table hq.acquisition_leads
  add column if not exists legal_entity_id uuid references hq.legal_entities(id) default '10000000-0000-0000-0000-000000000001',
  add column if not exists department_id uuid references hq.departments(id) default '30000000-0000-0000-0000-000000000011',
  add column if not exists created_by uuid references hq.employees(id),
  add column if not exists source_visit_id uuid references hq.field_visits(id),
  add column if not exists workflow_case_id uuid references hq.workflow_cases(id);
create unique index if not exists idx_acquisition_lead_source_visit on hq.acquisition_leads(source_visit_id) where source_visit_id is not null;
alter table hq.support_tickets
  add column if not exists ticket_number text,
  add column if not exists legal_entity_id uuid references hq.legal_entities(id) default '10000000-0000-0000-0000-000000000001',
  add column if not exists department_id uuid references hq.departments(id) default '30000000-0000-0000-0000-000000000010',
  add column if not exists current_department_id uuid references hq.departments(id) default '30000000-0000-0000-0000-000000000010',
  add column if not exists created_by uuid references hq.employees(id),
  add column if not exists workflow_case_id uuid references hq.workflow_cases(id),
  add column if not exists correlation_id uuid default gen_random_uuid();
update hq.support_tickets set ticket_number=hq.next_support_ticket_number() where ticket_number is null;
alter table hq.support_tickets alter column ticket_number set default hq.next_support_ticket_number();
alter table hq.support_tickets alter column ticket_number set not null;
create unique index if not exists idx_support_ticket_number on hq.support_tickets(ticket_number);
alter table hq.approval_requests add column if not exists workflow_case_id uuid references hq.workflow_cases(id);

create or replace function public.hq_submit_field_partner_workflow_v1(p_visit_id uuid,p_kyc_id uuid,p_actor_employee_id uuid) returns jsonb
language plpgsql security definer set search_path=hq,public as $$
declare v hq.field_visits%rowtype;k hq.field_kyc_cases%rowtype;c hq.workflow_cases%rowtype;l hq.acquisition_leads%rowtype;d record;owner_id uuid;
begin
  select * into v from hq.field_visits where id=p_visit_id for update;
  if not found then raise exception 'Missao Field inexistente'; end if;
  if v.visit_type<>'onboarding' then raise exception 'A missao nao e de onboarding'; end if;
  select * into k from hq.field_kyc_cases where id=p_kyc_id and visit_id=p_visit_id;
  if not found then raise exception 'KYC nao pertence a missao'; end if;
  select * into c from hq.workflow_cases where source_type='field_visit' and source_id=p_visit_id::text and case_type='partner_onboarding';
  if found then return jsonb_build_object('case',to_jsonb(c),'created',false); end if;
  select e.id into owner_id from hq.employees e join hq.departments d on d.id=e.department_id where d.code='ACQUISITION' and e.status='active' order by e.created_at limit 1;
  insert into hq.workflow_cases(legal_entity_id,platform_id,origin_department_id,current_department_id,case_type,title,source_type,source_id,created_by,assigned_to,status)
  values(coalesce(v.legal_entity_id,'10000000-0000-0000-0000-000000000001'),v.platform_id,'30000000-0000-0000-0000-000000000009','30000000-0000-0000-0000-000000000011','partner_onboarding','Onboarding: '||k.applicant_name,'field_visit',v.id::text,p_actor_employee_id,owner_id,'in_progress') returning * into c;
  insert into hq.acquisition_leads(platform_id,owner_id,name,contact,stage,status,organization_name,lead_type,source,notes,legal_entity_id,department_id,created_by,source_visit_id,workflow_case_id)
  values(v.platform_id,owner_id,k.applicant_name,k.entity_reference,'new','open',k.applicant_name,k.entity_type,'field',v.objective,coalesce(v.legal_entity_id,'10000000-0000-0000-0000-000000000001'),'30000000-0000-0000-0000-000000000011',p_actor_employee_id,v.id,c.id) returning * into l;
  update hq.field_visits set workflow_case_id=c.id where id=v.id;
  update hq.field_kyc_cases set workflow_case_id=c.id where id=k.id;
  insert into hq.workflow_links(case_id,resource_type,resource_id) values(c.id,'field_visit',v.id::text),(c.id,'field_kyc',k.id::text),(c.id,'acquisition_lead',l.id::text);
  for d in select * from (values(1,'ACQUISITION','commercial_review','pending'),(2,'COMPLIANCE','kyc_review','pending'),(3,'LEGAL','contract_review','blocked'),(4,'EXECUTIVE','partner_approval','blocked'),(5,'FINANCE','commercial_terms','blocked'),(6,'MARKETING','partner_launch','blocked')) x(step_order,code,step_type,status)
  loop insert into hq.workflow_steps(case_id,step_order,department_id,step_type,status) select c.id,d.step_order,id,d.step_type,d.status from hq.departments where code=d.code; end loop;
  insert into hq.notifications(employee_id,type,title,body,platform_id,target_url)
  select e.id,'workflow_assigned','Novo processo '||c.case_number,'Onboarding de '||k.applicant_name||' aguarda análise.',v.platform_id,'/aquisicao-parceiros'
  from hq.employees e join hq.departments dep on dep.id=e.department_id where e.status='active' and dep.code in('ACQUISITION','COMPLIANCE');
  insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,platform_id,module,target_type,target_id,result,correlation_id,metadata)
  values(p_actor_employee_id,'field_partner_workflow_created',c.legal_entity_id,c.platform_id,'workflow','workflow_case',c.id::text,'success',c.correlation_id,jsonb_build_object('case_number',c.case_number,'visit_id',v.id,'kyc_id',k.id,'lead_id',l.id));
  return jsonb_build_object('case',to_jsonb(c),'lead',to_jsonb(l),'created',true);
end $$;

revoke all on function public.hq_submit_field_partner_workflow_v1(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.hq_submit_field_partner_workflow_v1(uuid,uuid,uuid) to service_role;

create or replace function public.hq_route_support_ticket_v1(p_ticket_id uuid,p_department_code text,p_actor_employee_id uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path=hq,public as $$
declare t hq.support_tickets%rowtype;dep hq.departments%rowtype;c hq.workflow_cases%rowtype;assignee uuid;a hq.support_department_assignments%rowtype;
begin
  select * into t from hq.support_tickets where id=p_ticket_id for update;
  if not found then raise exception 'Ticket inexistente'; end if;
  if t.status='closed' then raise exception 'Ticket encerrado'; end if;
  select * into dep from hq.departments where code=upper(p_department_code) and active=true;
  if not found then raise exception 'Departamento inexistente'; end if;
  select id into assignee from hq.employees where department_id=dep.id and status='active' order by created_at limit 1;
  if t.workflow_case_id is null then
    insert into hq.workflow_cases(legal_entity_id,platform_id,origin_department_id,current_department_id,case_type,title,source_type,source_id,created_by,assigned_to,status)
    values(coalesce(t.legal_entity_id,'10000000-0000-0000-0000-000000000001'),t.platform_id,coalesce(t.department_id,'30000000-0000-0000-0000-000000000010'),dep.id,'support_case',t.ticket_number||' - '||t.subject,'support_ticket',t.id::text,p_actor_employee_id,assignee,'in_progress') returning * into c;
    insert into hq.workflow_links(case_id,resource_type,resource_id) values(c.id,'support_ticket',t.id::text);
  else select * into c from hq.workflow_cases where id=t.workflow_case_id for update; end if;
  update hq.workflow_cases set current_department_id=dep.id,assigned_to=assignee,status='in_progress',updated_at=now() where id=c.id;
  insert into hq.support_department_assignments(ticket_id,department_id,assigned_to,assigned_by,reason) values(t.id,dep.id,assignee,p_actor_employee_id,p_reason) returning * into a;
  update hq.support_tickets set workflow_case_id=c.id,current_department_id=dep.id,correlation_id=c.correlation_id,
    assigned_to=coalesce(assignee,assigned_to),assigned_by=p_actor_employee_id,
    escalated_to=case when dep.code<>'SUPPORT' and assignee is not null then assignee else escalated_to end,
    escalation_reason=case when dep.code<>'SUPPORT' and assignee is not null then p_reason else escalation_reason end,
    status=case when dep.code<>'SUPPORT' and assignee is not null then 'escalated' else case when status='open' then 'in_analysis' else status end end,
    updated_at=now() where id=t.id;
  insert into hq.workflow_steps(case_id,step_order,department_id,step_type,target_type,target_id,assigned_to,status,started_at)
  select c.id,coalesce(max(step_order),0)+1,dep.id,'support_response','support_ticket',t.id::text,assignee,'pending',now() from hq.workflow_steps where case_id=c.id;
  insert into hq.notifications(employee_id,type,title,body,platform_id,target_url)
  select e.id,'support_routed',t.ticket_number||' encaminhado',p_reason,t.platform_id,'/apoio-cliente' from hq.employees e where e.department_id=dep.id and e.status='active';
  insert into hq.support_history(ticket_id,event_type,description,actor_employee_id,metadata) values(t.id,'department_routed','Encaminhado para '||dep.name,p_actor_employee_id,jsonb_build_object('department_code',dep.code,'assignment_id',a.id,'case_number',c.case_number));
  insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,platform_id,module,target_type,target_id,result,correlation_id,metadata)
  values(p_actor_employee_id,'support_department_routed',coalesce(t.legal_entity_id,'10000000-0000-0000-0000-000000000001'),t.platform_id,'support','support_ticket',t.id::text,'success',c.correlation_id,jsonb_build_object('ticket_number',t.ticket_number,'department',dep.code,'reason',p_reason));
  return jsonb_build_object('case',to_jsonb(c),'assignment',to_jsonb(a),'ticket_number',t.ticket_number);
end $$;
revoke all on function public.hq_route_support_ticket_v1(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.hq_route_support_ticket_v1(uuid,text,uuid,text) to service_role;

create or replace function public.hq_decide_workflow_step_v1(p_step_id uuid,p_actor_employee_id uuid,p_decision text,p_result text,p_allow_override boolean default false) returns jsonb
language plpgsql security definer set search_path=hq,public as $$
declare s hq.workflow_steps%rowtype;c hq.workflow_cases%rowtype;actor_department uuid;approval_id uuid;
begin
  if p_decision not in('completed','rejected') or coalesce(length(trim(p_result)),0)<3 then raise exception 'Decisao ou resultado invalido'; end if;
  select * into s from hq.workflow_steps where id=p_step_id for update;if not found then raise exception 'Etapa inexistente';end if;
  select * into c from hq.workflow_cases where id=s.case_id for update;
  select department_id into actor_department from hq.employees where id=p_actor_employee_id and status='active';
  if not p_allow_override and actor_department is distinct from s.department_id then raise exception 'Etapa fora do departamento';end if;
  if s.status not in('pending','in_progress','waiting_approval') then raise exception 'Etapa nao esta disponivel';end if;
  update hq.workflow_steps set status=p_decision,result=p_result,completed_at=now(),updated_at=now() where id=s.id;
  if p_decision='rejected' then
    update hq.workflow_cases set status='rejected',updated_at=now() where id=c.id;
  elsif s.step_type in('commercial_review','kyc_review') and not exists(select 1 from hq.workflow_steps where case_id=c.id and step_type in('commercial_review','kyc_review') and id<>s.id and status<>'completed') then
    update hq.workflow_steps set status='pending',started_at=now(),updated_at=now() where case_id=c.id and step_type='contract_review' and status='blocked';
    update hq.workflow_cases set current_department_id=(select department_id from hq.workflow_steps where case_id=c.id and step_type='contract_review'),updated_at=now() where id=c.id;
  elsif s.step_type='contract_review' then
    update hq.workflow_steps set status='waiting_approval',started_at=now(),updated_at=now() where case_id=c.id and step_type='partner_approval';
    insert into hq.approval_requests(legal_entity_id,platform_id,department_id,request_type,target_type,target_id,title,status,required_approvals,requested_by,submitted_at,previous_state,workflow_case_id)
    values(c.legal_entity_id,c.platform_id,(select department_id from hq.workflow_steps where case_id=c.id and step_type='partner_approval'),'partner','workflow_case',c.id::text,'Aprovar parceiro - '||c.case_number,'submitted',1,p_actor_employee_id,now(),jsonb_build_object('workflow_status',c.status),c.id) returning id into approval_id;
    update hq.workflow_cases set status='waiting_approval',current_department_id=(select department_id from hq.workflow_steps where case_id=c.id and step_type='partner_approval'),updated_at=now() where id=c.id;
    insert into hq.notifications(employee_id,type,title,body,platform_id,target_url) select e.id,'approval_required','Aprovação '||c.case_number,c.title,c.platform_id,'/aprovacoes' from hq.employees e join hq.departments d on d.id=e.department_id where e.status='active' and d.code='EXECUTIVE';
  end if;
  insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,platform_id,module,target_type,target_id,result,correlation_id,metadata)
  values(p_actor_employee_id,'workflow_step_'||p_decision,c.legal_entity_id,c.platform_id,'workflow','workflow_step',s.id::text,'success',c.correlation_id,jsonb_build_object('case_number',c.case_number,'step_type',s.step_type,'result',p_result,'approval_id',approval_id));
  return jsonb_build_object('case_id',c.id,'case_number',c.case_number,'step_id',s.id,'decision',p_decision,'approval_id',approval_id);
end $$;
revoke all on function public.hq_decide_workflow_step_v1(uuid,uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.hq_decide_workflow_step_v1(uuid,uuid,text,text,boolean) to service_role;

create or replace function public.hq_apply_workflow_approval_v1(p_case_id uuid,p_actor_employee_id uuid,p_decision text,p_reason text default null) returns jsonb
language plpgsql security definer set search_path=hq,public as $$
declare c hq.workflow_cases%rowtype;s hq.workflow_steps%rowtype;
begin
  select * into c from hq.workflow_cases where id=p_case_id for update;if not found then raise exception 'Processo inexistente';end if;
  select * into s from hq.workflow_steps where case_id=c.id and step_type='partner_approval' for update;
  if s.status<>'waiting_approval' then raise exception 'Processo nao aguarda aprovacao';end if;
  if p_decision='approved' then
    update hq.workflow_steps set status='completed',result=coalesce(p_reason,'Aprovado'),completed_at=now(),updated_at=now() where id=s.id;
    update hq.workflow_steps set status='pending',started_at=now(),updated_at=now() where case_id=c.id and step_type in('commercial_terms','partner_launch') and status='blocked';
    update hq.workflow_cases set status='approved',current_department_id=null,updated_at=now() where id=c.id;
    insert into hq.notifications(employee_id,type,title,body,platform_id,target_url)
    select e.id,'workflow_approved',c.case_number||' aprovado',c.title,c.platform_id,case d.code when 'FINANCE' then '/financas' else '/marketing' end from hq.employees e join hq.departments d on d.id=e.department_id where e.status='active' and d.code in('FINANCE','MARKETING');
  else
    update hq.workflow_steps set status='rejected',result=coalesce(p_reason,'Rejeitado'),completed_at=now(),updated_at=now() where id=s.id;
    update hq.workflow_cases set status='rejected',updated_at=now() where id=c.id;
  end if;
  return jsonb_build_object('case_id',c.id,'case_number',c.case_number,'decision',p_decision);
end $$;
revoke all on function public.hq_apply_workflow_approval_v1(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.hq_apply_workflow_approval_v1(uuid,uuid,text,text) to service_role;
do $$ declare t text;begin foreach t in array array['workflow_cases','workflow_steps','workflow_links','support_department_assignments'] loop execute format('alter table hq.%I enable row level security',t);execute format('revoke all on hq.%I from public,anon,authenticated',t);execute format('grant all on hq.%I to service_role',t);end loop;end $$;
create index if not exists idx_workflow_cases_status on hq.workflow_cases(status,current_department_id,updated_at desc);
create index if not exists idx_workflow_steps_queue on hq.workflow_steps(department_id,status,created_at);
create index if not exists idx_support_department_ticket on hq.support_department_assignments(ticket_id,status,created_at);

commit;
