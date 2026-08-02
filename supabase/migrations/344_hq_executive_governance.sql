begin;
create table if not exists hq.board_meetings (
 id uuid primary key default gen_random_uuid(), title text not null, scheduled_at timestamptz not null, status text not null default 'scheduled' check(status in ('scheduled','held','cancelled')), minutes_url text, created_by uuid references hq.employees(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists hq.executive_decisions (
 id uuid primary key default gen_random_uuid(), title text not null, description text, category text not null check(category in ('strategy','governance','profit_distribution','corporate_change')), status text not null default 'draft' check(status in ('draft','proposed','approved','rejected','in_execution','completed')), meeting_id uuid references hq.board_meetings(id) on delete set null, responsible_employee_id uuid references hq.employees(id), due_at timestamptz, approved_at timestamptz, created_by uuid references hq.employees(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists hq.governance_documents (
 id uuid primary key default gen_random_uuid(), title text not null, document_type text not null, storage_path text not null, decision_id uuid references hq.executive_decisions(id) on delete set null, meeting_id uuid references hq.board_meetings(id) on delete set null, created_by uuid references hq.employees(id), created_at timestamptz not null default now()
);
create table if not exists hq.corporate_change_log (
 id uuid primary key default gen_random_uuid(), change_type text not null, summary text not null, effective_at timestamptz, decision_id uuid references hq.executive_decisions(id) on delete set null, created_by uuid references hq.employees(id), created_at timestamptz not null default now()
);
alter table hq.board_meetings enable row level security;
alter table hq.executive_decisions enable row level security;
alter table hq.governance_documents enable row level security;
alter table hq.corporate_change_log enable row level security;
revoke all on hq.board_meetings,hq.executive_decisions,hq.governance_documents,hq.corporate_change_log from public,anon,authenticated;
grant all on hq.board_meetings,hq.executive_decisions,hq.governance_documents,hq.corporate_change_log to service_role;
create index if not exists idx_hq_executive_decisions_due on hq.executive_decisions(status,due_at);
commit;
