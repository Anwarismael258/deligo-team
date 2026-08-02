begin;

do $$ declare constraint_name text; begin
  select c.conname into constraint_name from pg_constraint c join pg_class r on r.oid=c.conrelid join pg_namespace n on n.oid=r.relnamespace
  where n.nspname='hq' and r.relname='field_visits' and c.contype='c' and pg_get_constraintdef(c.oid) ilike '%status%' limit 1;
  if constraint_name is not null then execute format('alter table hq.field_visits drop constraint %I',constraint_name); end if;
end $$;

alter table hq.field_visits
  add column if not exists visit_type text not null default 'operational',
  add column if not exists priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
  add column if not exists address text,
  add column if not exists latitude numeric(9,6),
  add column if not exists longitude numeric(9,6),
  add column if not exists location_authorized boolean not null default false,
  add column if not exists evidence_required boolean not null default false,
  add column if not exists cancelled_reason text,
  add column if not exists updated_at timestamptz not null default now();
update hq.field_visits set location_authorized=true where location is not null;
alter table hq.field_visits add constraint field_visits_status_check check(status in ('planned','assigned','in_progress','blocked','completed','cancelled'));
alter table hq.field_visits add constraint field_visits_location_consent_check check(location_authorized or (location is null and latitude is null and longitude is null));

create table if not exists hq.field_checklists(
  id uuid primary key default gen_random_uuid(), visit_id uuid not null references hq.field_visits(id) on delete cascade,
  item_order integer not null default 1, title text not null, is_required boolean not null default true,
  status text not null default 'pending' check(status in ('pending','passed','failed','not_applicable')),
  notes text, verified_by uuid references hq.employees(id), verified_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists hq.field_evidence(
  id uuid primary key default gen_random_uuid(), visit_id uuid not null references hq.field_visits(id) on delete cascade,
  evidence_type text not null check(evidence_type in ('photo','document','signature','audio','note')),
  storage_reference text not null, latitude numeric(9,6), longitude numeric(9,6), captured_by uuid references hq.employees(id),
  captured_at timestamptz not null default now(), created_at timestamptz not null default now()
);
create table if not exists hq.field_reports(
  id uuid primary key default gen_random_uuid(), visit_id uuid not null references hq.field_visits(id) on delete cascade,
  summary text not null, outcome text not null check(outcome in ('successful','partial','failed','rescheduled')),
  follow_up_required boolean not null default false, follow_up_due timestamptz, created_by uuid references hq.employees(id),
  created_at timestamptz not null default now(), unique(visit_id)
);
create table if not exists hq.field_history(
  id uuid primary key default gen_random_uuid(), visit_id uuid not null references hq.field_visits(id) on delete cascade,
  event_type text not null, description text not null, actor_employee_id uuid references hq.employees(id), metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function hq.enforce_field_visit_transition() returns trigger language plpgsql security definer set search_path=hq,public as $$
begin
  if new.status<>old.status then
    if old.status='planned' and new.status not in ('assigned','in_progress','cancelled') then raise exception 'Transicao Field invalida'; end if;
    if old.status='assigned' and new.status not in ('in_progress','cancelled') then raise exception 'Transicao Field invalida'; end if;
    if old.status='in_progress' and new.status not in ('blocked','completed','cancelled') then raise exception 'Transicao Field invalida'; end if;
    if old.status='blocked' and new.status not in ('in_progress','cancelled') then raise exception 'Transicao Field invalida'; end if;
    if old.status in ('completed','cancelled') then raise exception 'Missao Field encerrada'; end if;
    if new.status='in_progress' then new.started_at:=coalesce(new.started_at,now()); end if;
    if new.status='completed' then
      if not exists(select 1 from hq.field_reports where visit_id=old.id) then raise exception 'Relatorio obrigatorio antes da conclusao'; end if;
      if new.evidence_required and not exists(select 1 from hq.field_evidence where visit_id=old.id) then raise exception 'Evidencia obrigatoria antes da conclusao'; end if;
      if exists(select 1 from hq.field_checklists where visit_id=old.id and is_required and status='pending') then raise exception 'Checklist obrigatoria incompleta'; end if;
      new.completed_at:=now();
    end if;
  end if;
  new.updated_at:=now(); return new;
end $$;
drop trigger if exists trg_field_visit_transition on hq.field_visits;
create trigger trg_field_visit_transition before update on hq.field_visits for each row execute function hq.enforce_field_visit_transition();

create index if not exists idx_field_visits_status_planned on hq.field_visits(status,planned_at);
create index if not exists idx_field_visits_worker on hq.field_visits(worker_id,status);
create index if not exists idx_field_history_visit on hq.field_history(visit_id,created_at desc);
do $$ declare t text; begin foreach t in array array['field_checklists','field_evidence','field_reports','field_history'] loop
  execute format('alter table hq.%I enable row level security',t);
  execute format('revoke all on hq.%I from public,anon,authenticated',t);
  execute format('grant all on hq.%I to service_role',t);
end loop; end $$;
revoke all on function hq.enforce_field_visit_transition() from public,anon,authenticated;
grant execute on function hq.enforce_field_visit_transition() to service_role;

commit;
