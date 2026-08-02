begin;

create table if not exists hq.projects (
  id uuid primary key default gen_random_uuid(),
  legal_entity_id uuid not null references hq.legal_entities(id),
  platform_id uuid references hq.platforms(id),
  department_id uuid references hq.departments(id),
  code text not null unique,
  name text not null,
  description text,
  objective text not null,
  owner_employee_id uuid not null references hq.employees(id),
  sponsor_employee_id uuid references hq.employees(id),
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status text not null default 'planned' check (status in ('planned','active','on_hold','completed','cancelled')),
  start_date date,
  due_date date,
  completed_at timestamptz,
  budget numeric(18,2) check (budget is null or budget >= 0),
  created_by uuid not null references hq.employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (due_date is null or start_date is null or due_date >= start_date)
);

alter table hq.tasks add column if not exists project_id uuid references hq.projects(id);
alter table hq.tasks add column if not exists parent_task_id uuid references hq.tasks(id);
alter table hq.tasks add column if not exists created_by uuid references hq.employees(id);
alter table hq.tasks add column if not exists objective text;
alter table hq.tasks add column if not exists estimated_hours numeric(10,2);
alter table hq.tasks add column if not exists progress smallint not null default 0;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='tasks_progress_range' and conrelid='hq.tasks'::regclass) then
    alter table hq.tasks add constraint tasks_progress_range check (progress between 0 and 100);
  end if;
  if not exists (select 1 from pg_constraint where conname='tasks_estimated_hours_nonnegative' and conrelid='hq.tasks'::regclass) then
    alter table hq.tasks add constraint tasks_estimated_hours_nonnegative check (estimated_hours is null or estimated_hours >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='tasks_parent_not_self' and conrelid='hq.tasks'::regclass) then
    alter table hq.tasks add constraint tasks_parent_not_self check (parent_task_id is null or parent_task_id <> id);
  end if;
end $$;

create table if not exists hq.project_members (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references hq.projects(id) on delete cascade,
  employee_id uuid not null references hq.employees(id),
  project_role text not null default 'member',
  allocation_percent smallint check (allocation_percent between 1 and 100),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  unique(project_id, employee_id)
);

create table if not exists hq.project_milestones (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references hq.projects(id) on delete cascade,
  title text not null,
  description text,
  due_date date,
  status text not null default 'pending' check (status in ('pending','in_progress','completed','missed','cancelled')),
  completed_at timestamptz,
  created_by uuid references hq.employees(id),
  created_at timestamptz not null default now()
);

create table if not exists hq.task_dependencies (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references hq.tasks(id) on delete cascade,
  depends_on_task_id uuid not null references hq.tasks(id) on delete cascade,
  dependency_type text not null default 'finish_to_start' check (dependency_type in ('finish_to_start','start_to_start','finish_to_finish')),
  created_by uuid references hq.employees(id),
  created_at timestamptz not null default now(),
  unique(task_id, depends_on_task_id),
  check(task_id <> depends_on_task_id)
);

create table if not exists hq.project_updates (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references hq.projects(id) on delete cascade,
  task_id uuid references hq.tasks(id) on delete cascade,
  update_type text not null default 'progress' check (update_type in ('progress','comment','risk','decision','blocker')),
  message text not null,
  progress smallint check (progress is null or progress between 0 and 100),
  created_by uuid not null references hq.employees(id),
  created_at timestamptz not null default now()
);

create or replace function hq.enforce_project_task_state() returns trigger language plpgsql security definer set search_path=hq,public as $$
declare p_status text;
begin
  if new.project_id is not null then
    select status into p_status from hq.projects where id=new.project_id;
    if p_status in ('completed','cancelled') and (tg_op='INSERT' or new.status is distinct from old.status) then
      raise exception 'Projeto encerrado';
    end if;
  end if;
  if new.status='completed' then new.progress:=100; new.completed_at:=coalesce(new.completed_at,now());
  elsif tg_op='UPDATE' and old.status='completed' then new.completed_at:=null; end if;
  new.updated_at:=now();
  return new;
end $$;
drop trigger if exists trg_project_task_state on hq.tasks;
create trigger trg_project_task_state before insert or update on hq.tasks for each row execute function hq.enforce_project_task_state();

create or replace function hq.touch_project() returns trigger language plpgsql as $$ begin new.updated_at:=now(); if new.status='completed' then new.completed_at:=coalesce(new.completed_at,now()); elsif old.status='completed' then new.completed_at:=null; end if; return new; end $$;
drop trigger if exists trg_touch_project on hq.projects;
create trigger trg_touch_project before update on hq.projects for each row execute function hq.touch_project();

do $$ declare t text; begin
  foreach t in array array['projects','project_members','project_milestones','task_dependencies','project_updates'] loop
    execute format('alter table hq.%I enable row level security',t);
    execute format('revoke all on hq.%I from public,anon,authenticated',t);
    execute format('grant all on hq.%I to service_role',t);
  end loop;
end $$;
revoke all on hq.tasks from public,anon,authenticated;
grant all on hq.tasks to service_role;

create index if not exists idx_projects_status_due on hq.projects(status,due_date);
create index if not exists idx_projects_owner on hq.projects(owner_employee_id,status);
create index if not exists idx_tasks_project_status on hq.tasks(project_id,status,due_at);
create index if not exists idx_project_updates_project on hq.project_updates(project_id,created_at desc);

commit;
