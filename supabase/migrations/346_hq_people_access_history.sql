begin;
create table if not exists hq.employee_permission_overrides (id uuid primary key default gen_random_uuid(), employee_id uuid not null references hq.employees(id) on delete cascade, permission_code text not null, allowed boolean not null, granted_by uuid references hq.employees(id), created_at timestamptz not null default now(), unique(employee_id,permission_code));
create table if not exists hq.employee_change_history (id uuid primary key default gen_random_uuid(), employee_id uuid not null references hq.employees(id) on delete cascade, actor_id uuid references hq.employees(id), action text not null, before_state jsonb, after_state jsonb, created_at timestamptz not null default now());
create table if not exists hq.employee_access_log (id uuid primary key default gen_random_uuid(), employee_id uuid references hq.employees(id) on delete set null, occurred_at timestamptz not null default now(), event_type text not null, metadata jsonb not null default '{}'::jsonb);
alter table hq.employee_permission_overrides enable row level security; alter table hq.employee_change_history enable row level security; alter table hq.employee_access_log enable row level security;
revoke all on hq.employee_permission_overrides,hq.employee_change_history,hq.employee_access_log from public,anon,authenticated;
grant all on hq.employee_permission_overrides,hq.employee_change_history,hq.employee_access_log to service_role;
create index if not exists idx_hq_employee_access_recent on hq.employee_access_log(employee_id,occurred_at desc);
commit;
