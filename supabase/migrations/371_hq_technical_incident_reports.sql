create table if not exists hq.technology_incident_reports(
  id uuid primary key default gen_random_uuid(),
  incident_id uuid not null unique references hq.technology_incidents(id) on delete cascade,
  workflow_case_id uuid references hq.workflow_cases(id) on delete set null,
  legal_entity_id uuid not null references hq.legal_entities(id),
  platform_id uuid references hq.platforms(id),
  title text not null,
  severity text not null,
  started_at timestamptz not null,
  resolved_at timestamptz not null,
  root_cause text,
  resolution text not null,
  executive_summary text not null,
  interventions jsonb not null default '[]'::jsonb,
  created_by uuid not null references hq.employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table hq.technology_incident_reports enable row level security;
revoke all on hq.technology_incident_reports from public,anon,authenticated;
grant all on hq.technology_incident_reports to service_role;
create index if not exists idx_technology_incident_reports_platform on hq.technology_incident_reports(platform_id,created_at desc);
create index if not exists idx_technology_incident_reports_workflow on hq.technology_incident_reports(workflow_case_id);
comment on table hq.technology_incident_reports is 'Relatório técnico permanente criado quando a etapa final do workflow de incidente é concluída.';
