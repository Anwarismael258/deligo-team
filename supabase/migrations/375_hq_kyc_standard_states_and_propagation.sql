begin;

alter table hq.field_kyc_cases drop constraint if exists field_kyc_cases_status_check;
alter table hq.field_kyc_cases
  add column if not exists applicant_data jsonb not null default '{}'::jsonb,
  add column if not exists risk_score numeric(6,2),
  add column if not exists risk_flags jsonb not null default '[]'::jsonb,
  add column if not exists submitted_at timestamptz,
  add column if not exists expires_at timestamptz,
  add column if not exists suspended_at timestamptz;
update hq.field_kyc_cases set status='submitted' where status='pending';
update hq.field_kyc_cases set status='under_review' where status='in_review';
alter table hq.field_kyc_cases add constraint field_kyc_cases_status_check check(status in('draft','submitted','documents_pending','under_review','field_verification_required','field_verification_in_progress','field_verification_completed','legal_review','approval_pending','approved','rejected','suspended','expired','correction_requested'));

create table if not exists hq.kyc_documents(
 id uuid primary key default gen_random_uuid(),
 kyc_case_id uuid not null references hq.field_kyc_cases(id) on delete cascade,
 document_type text not null,
 document_reference text,
 status text not null default 'received' check(status in('received','under_review','valid','invalid','expired','missing','replaced')),
 expiry_at timestamptz,
 rejection_reason text,
 uploaded_by uuid references hq.employees(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists idx_hq_kyc_documents_case on hq.kyc_documents(kyc_case_id,status,created_at desc);
alter table hq.kyc_documents enable row level security;
revoke all on hq.kyc_documents from public,anon,authenticated;
grant all on hq.kyc_documents to service_role;

create or replace function hq.propagate_kyc_decision() returns trigger
language plpgsql security definer set search_path=hq,public as $$
declare c hq.workflow_cases%rowtype;l hq.acquisition_leads%rowtype;d uuid;
begin
 if old.status is distinct from new.status then
  select * into c from hq.workflow_cases where id=new.workflow_case_id;
  if new.status='approved' then
   update hq.acquisition_leads set stage='qualified',updated_at=now() where workflow_case_id=new.workflow_case_id and status='open';
   for d in select id from hq.departments where code in('LEGAL','FINANCE') loop
    insert into hq.notifications(employee_id,type,title,body,platform_id,target_url,origin_department_id,priority,source_type,source_id)
    select e.id,'kyc_approved','KYC aprovado',new.applicant_name||' aguarda contrato e dados comerciais.',new.platform_id,'/aquisicao-parceiros',hq.workflow_department('COMPLIANCE'),'high','field_kyc_case',new.id::text
    from hq.employees e where e.department_id=d and e.status='active';
   end loop;
  end if;
  insert into hq.realtime_events(platform_id,department_id,workflow_case_id,topic,resource_type,resource_id,event_type,payload)
  values(new.platform_id,hq.workflow_department('COMPLIANCE'),new.workflow_case_id,'kyc','field_kyc_cases',new.id::text,'kyc.'||new.status,jsonb_build_object('status',new.status,'risk_score',new.risk_score));
 end if;
 return new;
end $$;
drop trigger if exists trg_hq_kyc_decision_propagation on hq.field_kyc_cases;
create trigger trg_hq_kyc_decision_propagation after update of status on hq.field_kyc_cases for each row execute function hq.propagate_kyc_decision();

commit;
