begin;
create table if not exists hq.assets(
 id uuid primary key default gen_random_uuid(),legal_entity_id uuid not null references hq.legal_entities(id),platform_id uuid references hq.platforms(id),
 asset_tag text not null unique,name text not null,asset_type text not null check(asset_type in('equipment','vehicle','sim_card','furniture','software','other')),
 serial_number text,manufacturer text,model text,status text not null default 'available' check(status in('available','assigned','maintenance','retired','lost','disposed')),
 department_id uuid references hq.departments(id),location text,acquired_on date,acquisition_cost numeric(18,2) check(acquisition_cost is null or acquisition_cost>=0),
 warranty_until date,notes text,created_by uuid references hq.employees(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists hq.asset_assignments(
 id uuid primary key default gen_random_uuid(),asset_id uuid not null references hq.assets(id),employee_id uuid not null references hq.employees(id),
 assigned_by uuid not null references hq.employees(id),assigned_at timestamptz not null default now(),expected_return_at timestamptz,returned_at timestamptz,
 condition_out text not null,condition_in text,status text not null default 'active' check(status in('active','returned','overdue','cancelled')),notes text
);
create unique index if not exists uq_asset_active_assignment on hq.asset_assignments(asset_id) where status='active';
create table if not exists hq.asset_maintenance(
 id uuid primary key default gen_random_uuid(),asset_id uuid not null references hq.assets(id),maintenance_type text not null,description text not null,
 provider text,cost numeric(18,2) not null default 0 check(cost>=0),status text not null default 'planned' check(status in('planned','in_progress','completed','cancelled')),
 scheduled_at timestamptz,started_at timestamptz,completed_at timestamptz,next_due_at timestamptz,created_by uuid references hq.employees(id),created_at timestamptz not null default now()
);
create table if not exists hq.asset_documents(
 id uuid primary key default gen_random_uuid(),asset_id uuid not null references hq.assets(id) on delete cascade,document_type text not null,title text not null,
 storage_reference text not null,uploaded_by uuid references hq.employees(id),created_at timestamptz not null default now()
);
create table if not exists hq.asset_history(
 id uuid primary key default gen_random_uuid(),asset_id uuid not null references hq.assets(id) on delete cascade,event_type text not null,description text not null,
 actor_employee_id uuid references hq.employees(id),before_state jsonb,after_state jsonb,created_at timestamptz not null default now()
);
create or replace function hq.enforce_asset_status() returns trigger language plpgsql security definer set search_path=hq,public as $$ begin
 if old.status in('retired','disposed') and new.status<>old.status then raise exception 'Ativo encerrado';end if;
 if new.status='assigned' and not exists(select 1 from hq.asset_assignments where asset_id=old.id and status='active') then raise exception 'Atribuicao ativa obrigatoria';end if;
 new.updated_at:=now();return new;end $$;
drop trigger if exists trg_asset_status on hq.assets;create trigger trg_asset_status before update on hq.assets for each row execute function hq.enforce_asset_status();
do $$ declare t text;begin foreach t in array array['assets','asset_assignments','asset_maintenance','asset_documents','asset_history'] loop execute format('alter table hq.%I enable row level security',t);execute format('revoke all on hq.%I from public,anon,authenticated',t);execute format('grant all on hq.%I to service_role',t);end loop;end $$;
create index if not exists idx_assets_status_type on hq.assets(status,asset_type);create index if not exists idx_asset_maintenance_due on hq.asset_maintenance(status,scheduled_at);create index if not exists idx_asset_history_asset on hq.asset_history(asset_id,created_at desc);
commit;
