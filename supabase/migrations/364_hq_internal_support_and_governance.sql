begin;

create table if not exists hq.internal_requests (
  id uuid primary key default gen_random_uuid(),
  request_number bigint generated always as identity unique,
  legal_entity_id uuid not null references hq.legal_entities(id),
  requester_id uuid not null references hq.employees(id),
  target_department_id uuid not null references hq.departments(id),
  assigned_to uuid references hq.employees(id),
  category text not null,
  subject text not null,
  description text not null,
  priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
  status text not null default 'open' check(status in ('open','assigned','in_progress','waiting_requester','resolved','closed','archived')),
  due_at timestamptz,
  resolution text,
  resolved_at timestamptz,
  closed_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists hq.internal_request_messages (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references hq.internal_requests(id) on delete cascade,
  author_employee_id uuid not null references hq.employees(id),
  message text not null check(length(trim(message)) >= 2),
  is_internal boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists hq.internal_request_history (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references hq.internal_requests(id) on delete cascade,
  actor_employee_id uuid not null references hq.employees(id),
  action text not null,
  previous_state jsonb,
  final_state jsonb,
  comment text,
  created_at timestamptz not null default now()
);

create or replace function hq.enforce_internal_request_state() returns trigger language plpgsql security definer set search_path=hq,public as $$
begin
  if old.status in ('closed','archived') and new.status <> old.status then raise exception 'Pedido encerrado'; end if;
  if new.status='resolved' and nullif(trim(new.resolution),'') is null then raise exception 'Resolucao obrigatoria'; end if;
  if new.status='closed' and old.status <> 'resolved' then raise exception 'Resolva antes de fechar'; end if;
  if new.status='archived' and old.status <> 'closed' then raise exception 'Feche antes de arquivar'; end if;
  if new.status='resolved' then new.resolved_at:=coalesce(new.resolved_at,now()); end if;
  if new.status='closed' then new.closed_at:=coalesce(new.closed_at,now()); end if;
  if new.status='archived' then new.archived_at:=coalesce(new.archived_at,now()); end if;
  new.updated_at:=now(); return new;
end $$;
drop trigger if exists trg_internal_request_state on hq.internal_requests;
create trigger trg_internal_request_state before update on hq.internal_requests for each row execute function hq.enforce_internal_request_state();

do $$ declare t text; begin
  foreach t in array array['internal_requests','internal_request_messages','internal_request_history'] loop
    execute format('alter table hq.%I enable row level security',t);
    execute format('revoke all on hq.%I from public,anon,authenticated',t);
    execute format('grant all on hq.%I to service_role',t);
  end loop;
end $$;

create index if not exists idx_internal_requests_department_status on hq.internal_requests(target_department_id,status,updated_at desc);
create index if not exists idx_internal_requests_requester on hq.internal_requests(requester_id,updated_at desc);
create index if not exists idx_internal_request_messages on hq.internal_request_messages(request_id,created_at);
create index if not exists idx_internal_request_history on hq.internal_request_history(request_id,created_at desc);

commit;
