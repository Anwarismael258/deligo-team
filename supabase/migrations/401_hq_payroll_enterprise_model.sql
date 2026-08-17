-- Enterprise payroll periods and worker lines. Existing hr_payroll_records remains
-- compatible; this is the richer model used by the new Payroll screen.
alter table hq.payroll_runs drop constraint if exists payroll_runs_status_check;
alter table hq.payroll_runs add constraint payroll_runs_status_check check(status in ('draft','calculated','validated','submitted_to_finance','pending_approval','approved','processing','paid','reconciled','failed','cancelled'));
alter table hq.payroll_runs add column if not exists period_label text;
alter table hq.payroll_runs add column if not exists validated_by uuid references hq.employees(id) on delete set null;
alter table hq.payroll_runs add column if not exists submitted_to_finance_at timestamptz;
alter table hq.payroll_runs add column if not exists paid_at timestamptz;
alter table hq.payroll_runs add column if not exists reconciled_at timestamptz;

create table if not exists hq.payroll_lines (
  id uuid primary key default gen_random_uuid(), payroll_run_id uuid not null references hq.payroll_runs(id) on delete cascade,
  employee_id uuid not null references hq.employees(id) on delete restrict,
  base_salary numeric(18,2) not null default 0 check(base_salary>=0), allowances numeric(18,2) not null default 0 check(allowances>=0),
  bonuses numeric(18,2) not null default 0 check(bonuses>=0), overtime numeric(18,2) not null default 0 check(overtime>=0), other_credits numeric(18,2) not null default 0 check(other_credits>=0),
  absences_deductions numeric(18,2) not null default 0 check(absences_deductions>=0), other_deductions numeric(18,2) not null default 0 check(other_deductions>=0),
  gross_amount numeric(18,2) generated always as (base_salary+allowances+bonuses+overtime+other_credits) stored,
  net_amount numeric(18,2) generated always as (base_salary+allowances+bonuses+overtime+other_credits-absences_deductions-other_deductions) stored,
  currency char(3) not null default 'MZN', status text not null default 'draft' check(status in ('draft','calculated','validated','approved','paid','reconciled','void')),
  payout_request_id uuid references hq.payout_requests(id) on delete set null, provider_reference text, paid_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(payroll_run_id,employee_id)
);
create table if not exists hq.payroll_line_history (
  id uuid primary key default gen_random_uuid(), payroll_line_id uuid not null references hq.payroll_lines(id) on delete cascade,
  action text not null, before_state jsonb, after_state jsonb, actor_employee_id uuid references hq.employees(id) on delete set null, created_at timestamptz not null default now()
);
create index if not exists hq_payroll_lines_employee_idx on hq.payroll_lines(employee_id,created_at desc);
alter table hq.payroll_lines enable row level security; alter table hq.payroll_line_history enable row level security;
grant select,insert,update on hq.payroll_lines,hq.payroll_line_history to service_role;
comment on table hq.payroll_lines is 'Payroll components and derived gross/net values; employee self-service reads only own approved lines through an authorized API.';
notify pgrst, 'reload schema';
