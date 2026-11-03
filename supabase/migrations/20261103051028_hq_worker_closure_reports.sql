begin;

create table if not exists hq.employee_closure_reports (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references hq.employees(id) on delete restrict,
  actor_employee_id uuid references hq.employees(id) on delete set null,
  reason text not null,
  verification_code text not null unique,
  integrity_hash text not null,
  canonical_payload jsonb not null,
  generated_at timestamptz not null default now()
);

create index if not exists idx_hq_employee_closure_reports_employee
  on hq.employee_closure_reports(employee_id, generated_at desc);

alter table hq.employee_closure_reports enable row level security;
revoke all on hq.employee_closure_reports from public, anon, authenticated;
grant all on hq.employee_closure_reports to service_role;

create or replace function hq.prevent_employee_closure_report_mutation()
returns trigger
language plpgsql
security definer
set search_path = hq, public, pg_temp
as $$
begin
  raise exception 'employee_closure_report_is_append_only';
end;
$$;

revoke all on function hq.prevent_employee_closure_report_mutation() from public, anon, authenticated;
grant execute on function hq.prevent_employee_closure_report_mutation() to service_role;

drop trigger if exists trg_employee_closure_reports_append_only on hq.employee_closure_reports;
create trigger trg_employee_closure_reports_append_only
before update or delete on hq.employee_closure_reports
for each row execute function hq.prevent_employee_closure_report_mutation();

commit;
