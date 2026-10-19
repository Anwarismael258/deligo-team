begin;

-- Hybrid task contract: manual tasks remain supported, while automatic tasks
-- carry their real source and can be safely re-emitted without duplicates.
alter table hq.tasks
  add column if not exists task_origin text not null default 'manual',
  add column if not exists task_type text not null default 'general',
  add column if not exists source_type text,
  add column if not exists source_id text,
  add column if not exists dedupe_key text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='hq_tasks_origin_check' and conrelid='hq.tasks'::regclass) then
    alter table hq.tasks add constraint hq_tasks_origin_check check (task_origin in ('manual','automatic'));
  end if;
end $$;

create unique index if not exists uq_hq_tasks_automatic_source
  on hq.tasks(dedupe_key) where task_origin='automatic' and dedupe_key is not null;
create index if not exists idx_hq_tasks_origin_type on hq.tasks(task_origin,task_type,status,due_at);
create index if not exists idx_hq_tasks_source on hq.tasks(source_type,source_id);

create or replace function hq.create_automatic_task(
  p_source_type text,
  p_source_id text,
  p_task_type text,
  p_title text,
  p_description text,
  p_assigned_to uuid,
  p_department_id uuid,
  p_platform_id uuid,
  p_priority text default 'normal',
  p_due_at timestamptz default null
) returns uuid
language plpgsql security definer set search_path=hq,public as $$
declare
  v_id uuid;
  v_assignee uuid := p_assigned_to;
begin
  if nullif(trim(p_source_type),'') is null or nullif(trim(p_source_id),'') is null then
    raise exception 'Fonte da tarefa automática obrigatória';
  end if;
  if v_assignee is null and p_department_id is not null then
    select id into v_assignee from hq.employees
    where department_id=p_department_id and status='active'
    order by created_at asc limit 1;
  end if;
  if v_assignee is null then return null; end if;

  insert into hq.tasks(
    legal_entity_id,platform_id,department_id,title,description,priority,status,
    assigned_to,assigned_by,due_at,task_origin,task_type,source_type,source_id,dedupe_key
  ) values (
    '10000000-0000-0000-0000-000000000001',p_platform_id,p_department_id,
    p_title,p_description,case when p_priority in ('low','normal','high','urgent') then p_priority else 'normal' end,
    'planned',v_assignee,null,p_due_at,'automatic',p_task_type,p_source_type,p_source_id,
    'automatic:'||p_source_type||':'||p_source_id||':'||p_task_type
  ) on conflict (dedupe_key) where task_origin='automatic' and dedupe_key is not null
    do update set assigned_to=excluded.assigned_to,department_id=excluded.department_id,
      platform_id=excluded.platform_id, title=excluded.title, description=excluded.description,
      priority=excluded.priority, due_at=excluded.due_at, updated_at=now()
    returning id into v_id;

  return v_id;
end $$;

-- Workflow steps are the canonical bridge for KYC, support, field and
-- marketing flows. They are already created by the existing orchestration.
create or replace function hq.task_from_workflow_step() returns trigger
language plpgsql security definer set search_path=hq,public as $$
declare c hq.workflow_cases%rowtype; d text; t text;
begin
  if new.status not in ('pending','in_progress','waiting_approval') or new.assigned_to is null then return new; end if;
  select * into c from hq.workflow_cases where id=new.case_id;
  if not found then return new; end if;
  d:=case when c.case_type='support_case' then 'support_reply'
          when c.case_type='partner_onboarding' then 'field_visit'
          when c.case_type='incident' then 'incident_followup'
          else 'workflow_step' end;
  perform hq.create_automatic_task(
    'workflow_step',new.id::text,d,
    coalesce(c.title,'Etapa de processo')||' · '||new.step_type,
    coalesce(new.result,'Processo requer execução nesta etapa.'),new.assigned_to,
    new.department_id,c.platform_id,case when new.status='waiting_approval' then 'high' else 'normal' end,null
  );
  return new;
end $$;
drop trigger if exists trg_hq_task_from_workflow_step on hq.workflow_steps;
create trigger trg_hq_task_from_workflow_step
after insert or update of status,assigned_to on hq.workflow_steps
for each row execute function hq.task_from_workflow_step();

create or replace function hq.task_from_approval_request() returns trigger
language plpgsql security definer set search_path=hq,public as $$
begin
  if new.status not in ('submitted','under_review') then return new; end if;
  perform hq.create_automatic_task(
    'approval_request',new.id::text,'approval',new.title,
    'Aprovação necessária: '||new.request_type,null,new.department_id,new.platform_id,
    coalesce(new.priority,'normal'),null
  );
  return new;
end $$;
drop trigger if exists trg_hq_task_from_approval_request on hq.approval_requests;
create trigger trg_hq_task_from_approval_request
after insert or update of status on hq.approval_requests
for each row execute function hq.task_from_approval_request();

create or replace function hq.task_from_support_ticket() returns trigger
language plpgsql security definer set search_path=hq,public as $$
begin
  if new.status in ('resolved','closed') or new.assigned_to is null then return new; end if;
  perform hq.create_automatic_task(
    'support_ticket',new.id::text,'support_reply',new.subject,
    'Responder ao atendimento e manter o histórico actualizado.',new.assigned_to,
    new.current_department_id,new.platform_id,new.priority,null
  );
  return new;
end $$;
drop trigger if exists trg_hq_task_from_support_ticket on hq.support_tickets;
create trigger trg_hq_task_from_support_ticket
after insert or update of status,assigned_to on hq.support_tickets
for each row execute function hq.task_from_support_ticket();

create or replace function hq.task_from_field_kyc() returns trigger
language plpgsql security definer set search_path=hq,public as $$
begin
  if new.status not in ('submitted','under_review','field_verification_required','approval_pending') then return new; end if;
  perform hq.create_automatic_task(
    'field_kyc_case',new.id::text,'kyc_review','KYC para revisão · '||new.applicant_name,
    'Consultar documentos, registar anotação e decidir o próximo passo.',null,
    hq.workflow_department('FIELD'),new.platform_id,'high',null
  );
  return new;
end $$;
drop trigger if exists trg_hq_task_from_field_kyc on hq.field_kyc_cases;
create trigger trg_hq_task_from_field_kyc
after insert or update of status on hq.field_kyc_cases
for each row execute function hq.task_from_field_kyc();

revoke all on function hq.create_automatic_task(text,text,text,text,text,uuid,uuid,uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function hq.create_automatic_task(text,text,text,text,text,uuid,uuid,uuid,text,timestamptz) to service_role;
revoke all on function hq.task_from_workflow_step() from public,anon,authenticated;
revoke all on function hq.task_from_approval_request() from public,anon,authenticated;
revoke all on function hq.task_from_support_ticket() from public,anon,authenticated;
revoke all on function hq.task_from_field_kyc() from public,anon,authenticated;

commit;
