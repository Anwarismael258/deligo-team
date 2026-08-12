begin;
create table if not exists core.hq_homologation_records (
  id uuid primary key default gen_random_uuid(),
  module text not null,
  app_slug text references core.apps(slug),
  record_type text not null,
  title text not null,
  description text,
  status text not null default 'draft',
  priority text not null default 'normal',
  amount_minor bigint,
  currency_code char(3) default 'MZN',
  assigned_to uuid references core.profiles(user_id),
  created_by_test_persona text not null,
  payload jsonb not null default '{}'::jsonb,
  is_test boolean not null default true check (is_test),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists hq_homologation_records_module_idx on core.hq_homologation_records(module, app_slug, status);
alter table core.hq_homologation_records enable row level security;
revoke all on core.hq_homologation_records from anon, authenticated;
grant all on core.hq_homologation_records to service_role;
create table if not exists core.hq_homologation_audit (
  id bigint generated always as identity primary key,
  record_id uuid,
  actor_persona text not null,
  action text not null,
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);
alter table core.hq_homologation_audit enable row level security;
revoke all on core.hq_homologation_audit from anon, authenticated;
grant all on core.hq_homologation_audit to service_role;
comment on table core.hq_homologation_records is 'Test-only HQ records. Must not accept is_test=false before corporate authentication cutover.';
comment on table core.hq_homologation_audit is 'Immutable audit trail for HQ homologation actions.';
commit;
