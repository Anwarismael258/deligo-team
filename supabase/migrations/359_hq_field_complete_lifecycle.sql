begin;

alter table hq.field_visits
  add column if not exists objective text,
  add column if not exists result text,
  add column if not exists checked_in_at timestamptz,
  add column if not exists checked_out_at timestamptz,
  add column if not exists checkin_latitude numeric(9,6),
  add column if not exists checkin_longitude numeric(9,6),
  add column if not exists checkout_latitude numeric(9,6),
  add column if not exists checkout_longitude numeric(9,6);

create table if not exists hq.field_verifications(
  id uuid primary key default gen_random_uuid(), visit_id uuid not null references hq.field_visits(id) on delete cascade,
  verification_type text not null, subject_reference text, observations text,
  status text not null default 'pending' check(status in ('pending','approved','rejected','correction_requested')),
  submitted_by uuid references hq.employees(id), reviewed_by uuid references hq.employees(id), review_reason text,
  submitted_at timestamptz not null default now(), reviewed_at timestamptz,
  check(status='pending' or reviewed_by is not null)
);
create table if not exists hq.field_kyc_cases(
  id uuid primary key default gen_random_uuid(), visit_id uuid references hq.field_visits(id) on delete set null,
  platform_id uuid not null references hq.platforms(id), applicant_name text not null, entity_type text not null,
  entity_reference text not null, document_references jsonb not null default '[]'::jsonb,
  status text not null default 'pending' check(status in ('pending','in_review','approved','rejected','correction_requested')),
  created_by uuid references hq.employees(id), reviewed_by uuid references hq.employees(id), review_reason text,
  created_at timestamptz not null default now(), reviewed_at timestamptz, unique(platform_id,entity_type,entity_reference)
);
create table if not exists hq.field_form_templates(
  id uuid primary key default gen_random_uuid(), title text not null, description text, form_schema jsonb not null default '[]'::jsonb,
  status text not null default 'active' check(status in ('draft','active','archived')), created_by uuid references hq.employees(id),
  created_at timestamptz not null default now()
);
create table if not exists hq.field_form_responses(
  id uuid primary key default gen_random_uuid(), visit_id uuid not null references hq.field_visits(id) on delete cascade,
  form_id uuid not null references hq.field_form_templates(id), answers jsonb not null default '{}'::jsonb,
  observations text, completed_by uuid references hq.employees(id), completed_at timestamptz not null default now()
);
create table if not exists hq.field_incidents(
  id uuid primary key default gen_random_uuid(), visit_id uuid not null references hq.field_visits(id) on delete cascade,
  title text not null, severity text not null check(severity in ('low','medium','high','critical')), description text not null,
  status text not null default 'open' check(status in ('open','investigating','resolved','closed')),
  reported_by uuid references hq.employees(id), reported_at timestamptz not null default now(), resolved_at timestamptz
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
      if coalesce(trim(new.objective),'')='' or coalesce(trim(new.result),'')='' then raise exception 'Objetivo e resultado sao obrigatorios'; end if;
      if new.checked_in_at is null or new.checked_out_at is null then raise exception 'Check-in e check-out obrigatorios'; end if;
      if not exists(select 1 from hq.field_reports where visit_id=old.id) then raise exception 'Relatorio obrigatorio antes da conclusao'; end if;
      if new.evidence_required and not exists(select 1 from hq.field_evidence where visit_id=old.id) then raise exception 'Evidencia obrigatoria antes da conclusao'; end if;
      if exists(select 1 from hq.field_checklists where visit_id=old.id and is_required and status='pending') then raise exception 'Checklist obrigatoria incompleta'; end if;
      if exists(select 1 from hq.field_verifications where visit_id=old.id and status='pending') then raise exception 'Verificacao pendente de decisao'; end if;
      new.completed_at:=now();
    end if;
  end if;
  if not new.location_authorized and (new.checkin_latitude is not null or new.checkin_longitude is not null or new.checkout_latitude is not null or new.checkout_longitude is not null) then raise exception 'Localizacao sem autorizacao'; end if;
  new.updated_at:=now(); return new;
end $$;

create index if not exists idx_field_verifications_status on hq.field_verifications(status,submitted_at);
create index if not exists idx_field_kyc_status on hq.field_kyc_cases(status,created_at);
create index if not exists idx_field_incidents_status on hq.field_incidents(status,severity);
do $$ declare t text; begin foreach t in array array['field_verifications','field_kyc_cases','field_form_templates','field_form_responses','field_incidents'] loop
  execute format('alter table hq.%I enable row level security',t);
  execute format('revoke all on hq.%I from public,anon,authenticated',t);
  execute format('grant all on hq.%I to service_role',t);
end loop; end $$;

commit;
