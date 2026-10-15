begin;

alter table hq.approval_requests
  add column if not exists category text not null default 'operational',
  add column if not exists policy_version integer not null default 1,
  add column if not exists delegable boolean not null default true,
  add column if not exists decision_deadline timestamptz;

alter table hq.approval_decisions
  add column if not exists reason text,
  add column if not exists previous_state jsonb not null default '{}'::jsonb,
  add column if not exists final_state jsonb not null default '{}'::jsonb;

alter table hq.approval_requests drop constraint if exists approval_requests_status_check;
alter table hq.approval_requests add constraint approval_requests_status_check
  check (status in ('draft','submitted','under_review','correction_requested','approved','rejected','cancelled','completed'));
alter table hq.approval_decisions drop constraint if exists approval_decisions_decision_check;
alter table hq.approval_decisions add constraint approval_decisions_decision_check
  check (decision in ('approved','rejected','returned'));

create index if not exists idx_hq_approval_requests_category_status
  on hq.approval_requests(category,status,decision_deadline);

commit;
