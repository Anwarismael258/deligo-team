begin;

alter table hq.approval_requests
  add column if not exists department_id uuid references hq.departments(id),
  add column if not exists reason text,
  add column if not exists previous_state jsonb,
  add column if not exists final_state jsonb;
alter table hq.approval_decisions
  add column if not exists reason text,
  add column if not exists previous_state jsonb,
  add column if not exists final_state jsonb;

create table if not exists hq.approval_type_permissions(
  request_type text not null, permission_code text not null, description text, primary key(request_type,permission_code)
);
insert into hq.approval_type_permissions(request_type,permission_code,description) values
 ('purchase','approval.purchase.decide','Compras'),('expense','approval.expense.decide','Despesas'),('contract','approval.contract.decide','Contratos'),
 ('marketing_publication','approval.campaign.decide','Campanhas'),('campaign','approval.campaign.decide','Campanhas'),('leave','approval.leave.decide','Férias'),
 ('payment','approval.payment.decide','Pagamentos'),('partner','approval.partner.decide','Parceiros'),('kyc','approval.kyc.decide','KYC'),
 ('critical_change','approval.critical.decide','Alterações críticas') on conflict do nothing;
insert into hq.permissions(code,module,action,data_class,description)
select distinct permission_code,'approvals','decide','restricted',description from hq.approval_type_permissions on conflict(code) do nothing;

create table if not exists hq.bi_targets(
  id uuid primary key default gen_random_uuid(), metric_code text not null, platform_id uuid references hq.platforms(id), department_id uuid references hq.departments(id),
  period_start date not null, period_end date not null, target_value numeric(18,2) not null, unit text not null, created_by uuid references hq.employees(id),
  created_at timestamptz not null default now(), unique nulls not distinct(metric_code,platform_id,department_id,period_start,period_end)
);
create table if not exists hq.saved_reports(
  id uuid primary key default gen_random_uuid(), name text not null, report_type text not null, filters jsonb not null default '{}'::jsonb,
  created_by uuid references hq.employees(id), created_at timestamptz not null default now(), last_generated_at timestamptz
);
create table if not exists hq.report_schedules(
  id uuid primary key default gen_random_uuid(), saved_report_id uuid not null references hq.saved_reports(id) on delete cascade,
  frequency text not null check(frequency in ('daily','weekly','monthly','quarterly')), recipient_reference text not null,
  next_run_at timestamptz not null, status text not null default 'active' check(status in ('active','paused','completed')), created_by uuid references hq.employees(id), created_at timestamptz not null default now()
);
create table if not exists hq.report_runs(
  id uuid primary key default gen_random_uuid(), saved_report_id uuid references hq.saved_reports(id) on delete set null,
  report_type text not null, filters jsonb not null default '{}'::jsonb, format text not null, row_count integer not null default 0,
  generated_by uuid references hq.employees(id), generated_at timestamptz not null default now()
);

alter table hq.audit_logs
  add column if not exists before_state jsonb,
  add column if not exists after_state jsonb,
  add column if not exists device text,
  add column if not exists request_path text;

create index if not exists idx_approval_queue on hq.approval_requests(status,request_type,submitted_at);
create index if not exists idx_report_schedules_next on hq.report_schedules(status,next_run_at);
create index if not exists idx_audit_module_time on hq.audit_logs(module,occurred_at desc);
do $$ declare t text; begin foreach t in array array['approval_type_permissions','bi_targets','saved_reports','report_schedules','report_runs'] loop
  execute format('alter table hq.%I enable row level security',t);
  execute format('revoke all on hq.%I from public,anon,authenticated',t);
  execute format('grant all on hq.%I to service_role',t);
end loop; end $$;

commit;
