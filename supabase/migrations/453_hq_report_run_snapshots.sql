begin;
alter table hq.report_runs
  add column if not exists period_start date,
  add column if not exists period_end date,
  add column if not exists snapshot jsonb not null default '{}'::jsonb,
  add column if not exists status text not null default 'completed';
create index if not exists idx_hq_report_runs_period on hq.report_runs(report_type,period_start,period_end,generated_at desc);
commit;
