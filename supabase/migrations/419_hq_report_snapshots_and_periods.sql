begin;
alter table hq.saved_reports
  add column if not exists period_start date,
  add column if not exists period_end date,
  add column if not exists platform_id uuid references hq.platforms(id),
  add column if not exists department_id uuid references hq.departments(id),
  add column if not exists status text not null default 'generated',
  add column if not exists version integer not null default 1,
  add column if not exists snapshot jsonb not null default '{}'::jsonb,
  add column if not exists confidentiality text not null default 'internal';
alter table hq.report_schedules drop constraint if exists report_schedules_frequency_check;
alter table hq.report_schedules add constraint report_schedules_frequency_check check(frequency in ('daily','weekly','monthly','quarterly','yearly'));
alter table hq.saved_reports drop constraint if exists saved_reports_status_check;
alter table hq.saved_reports add constraint saved_reports_status_check check(status in ('draft','generated','in_review','approved','final','archived'));
create index if not exists idx_hq_saved_reports_period on hq.saved_reports(report_type,period_start,period_end,created_at desc);
commit;
