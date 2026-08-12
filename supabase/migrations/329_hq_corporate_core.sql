begin;
create extension if not exists pgcrypto;
create schema if not exists hq;
revoke all on schema hq from anon, authenticated;
grant usage on schema hq to service_role;
create table if not exists hq.legal_entities (
  id uuid primary key default gen_random_uuid(), legal_name text not null unique,
  legal_form text not null, registration_number text, tax_number text,
  country_code text not null default 'MZ', base_currency text not null default 'MZN',
  status text not null default 'active' check (status in ('active','inactive','dissolved')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists hq.platforms (
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  slug text not null unique, name text not null, schema_name text not null unique,
  status text not null default 'active' check (status in ('active','inactive','maintenance')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists hq.departments (
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  code text not null, name text not null, parent_id uuid references hq.departments(id), active boolean not null default true,
  created_at timestamptz not null default now(), unique (legal_entity_id, code)
);
create table if not exists hq.employees (
  id uuid primary key default gen_random_uuid(), employee_code text not null unique,
  auth_user_id uuid unique, legal_entity_id uuid not null references hq.legal_entities(id),
  department_id uuid references hq.departments(id), manager_id uuid references hq.employees(id),
  display_name text not null, corporate_email text, phone_e164 text, job_title text not null,
  status text not null default 'invited' check (status in ('invited','active','suspended','offboarded')),
  joined_on date, valid_until timestamptz, last_login_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists hq.roles (
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  code text not null, name text not null, scope text not null check (scope in ('global','department','platform','self')),
  system_role boolean not null default false, active boolean not null default true,
  created_at timestamptz not null default now(), unique (legal_entity_id, code)
);
create table if not exists hq.permissions (
  id uuid primary key default gen_random_uuid(), code text not null unique, module text not null,
  action text not null, data_class text not null default 'internal', description text,
  created_at timestamptz not null default now()
);
create table if not exists hq.employee_roles (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references hq.employees(id),
  role_id uuid not null references hq.roles(id), department_id uuid references hq.departments(id),
  platform_id uuid references hq.platforms(id), granted_by uuid references hq.employees(id),
  valid_from timestamptz not null default now(), valid_until timestamptz, revoked_at timestamptz,
  created_at timestamptz not null default now(), unique nulls not distinct (employee_id, role_id, department_id, platform_id)
);
create table if not exists hq.role_permissions (
  role_id uuid not null references hq.roles(id) on delete cascade,
  permission_id uuid not null references hq.permissions(id) on delete cascade,
  effect text not null default 'allow' check (effect in ('allow','deny')),
  primary key (role_id, permission_id)
);
create table if not exists hq.employee_platforms (
  employee_id uuid not null references hq.employees(id), platform_id uuid not null references hq.platforms(id),
  granted_by uuid references hq.employees(id), valid_from timestamptz not null default now(),
  valid_until timestamptz, revoked_at timestamptz, primary key (employee_id, platform_id)
);
create table if not exists hq.shareholders (
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  employee_id uuid references hq.employees(id), display_name text not null,
  quota_percent numeric(5,2) not null check (quota_percent > 0 and quota_percent <= 100),
  quota_nominal_value numeric(18,2), effective_from date not null, effective_until date,
  is_managing_partner boolean not null default false, source_document_id uuid,
  created_at timestamptz not null default now()
);
create table if not exists hq.ownership_history (
  id uuid primary key default gen_random_uuid(), shareholder_id uuid not null references hq.shareholders(id),
  previous_percent numeric(5,2), new_percent numeric(5,2) not null,
  resolution_reference text not null, changed_by uuid references hq.employees(id), changed_at timestamptz not null default now()
);
create table if not exists hq.approval_requests (
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  platform_id uuid references hq.platforms(id), request_type text not null, target_type text not null,
  target_id text, title text not null, amount numeric(18,2), currency text default 'MZN',
  status text not null default 'draft' check (status in ('draft','submitted','under_review','approved','rejected','cancelled','completed')),
  required_approvals integer not null default 1 check (required_approvals > 0),
  requested_by uuid not null references hq.employees(id), submitted_at timestamptz,
  completed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists hq.approval_decisions (
  id uuid primary key default gen_random_uuid(), request_id uuid not null references hq.approval_requests(id) on delete cascade,
  approver_id uuid not null references hq.employees(id), decision text not null check (decision in ('approved','rejected')),
  comments text, decided_at timestamptz not null default now(), unique (request_id, approver_id)
);
create table if not exists hq.audit_logs (
  id uuid primary key default gen_random_uuid(), occurred_at timestamptz not null default now(),
  actor_employee_id uuid references hq.employees(id), action text not null, legal_entity_id uuid references hq.legal_entities(id),
  platform_id uuid references hq.platforms(id), module text, target_type text, target_id text,
  result text not null check (result in ('success','denied','error')), ip_address inet,
  user_agent text, session_id uuid, correlation_id uuid not null default gen_random_uuid(), metadata jsonb not null default '{}'::jsonb
);
create table if not exists hq.login_sessions (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references hq.employees(id),
  auth_session_id text unique, started_at timestamptz not null default now(), last_seen_at timestamptz not null default now(),
  ended_at timestamptz, revoked_at timestamptz, ip_address inet, user_agent text, device_name text,
  second_factor_verified boolean not null default false
);
create table if not exists hq.notifications (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references hq.employees(id),
  type text not null, title text not null, body text not null, platform_id uuid references hq.platforms(id),
  target_url text, read_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists hq.tasks (
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  platform_id uuid references hq.platforms(id), department_id uuid references hq.departments(id),
  title text not null, description text, priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status text not null default 'planned' check (status in ('planned','in_progress','blocked','completed','cancelled')),
  assigned_to uuid references hq.employees(id), assigned_by uuid references hq.employees(id), due_at timestamptz,
  completed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists hq.employee_activity (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references hq.employees(id),
  platform_id uuid references hq.platforms(id), department_id uuid references hq.departments(id),
  activity_type text not null, summary text not null, status text, source_type text, source_id text,
  occurred_at timestamptz not null default now(), metadata jsonb not null default '{}'::jsonb
);
create table if not exists hq.financial_accounts (
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  platform_id uuid references hq.platforms(id), account_type text not null check (account_type in ('corporate_bank','corporate_cash','user_wallet_control','platform_operational','receivable','payable')),
  name text not null, bank_name text, masked_account_number text, currency text not null default 'MZN',
  status text not null default 'active' check (status in ('active','inactive','closed')), created_at timestamptz not null default now()
);
create table if not exists hq.financial_transactions (
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  platform_id uuid references hq.platforms(id), account_id uuid references hq.financial_accounts(id),
  external_reference text, transaction_type text not null, classification text,
  amount numeric(18,2) not null check (amount >= 0), currency text not null default 'MZN',
  status text not null default 'pending' check (status in ('draft','pending','approved','posted','reconciled','rejected','reversed')),
  occurred_at timestamptz not null, created_by uuid references hq.employees(id), approved_by uuid references hq.employees(id),
  reconciled_by uuid references hq.employees(id), created_at timestamptz not null default now(),
  check (created_by is null or approved_by is null or created_by <> approved_by),
  check (approved_by is null or reconciled_by is null or approved_by <> reconciled_by)
);
create table if not exists hq.budgets (
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  platform_id uuid references hq.platforms(id), department_id uuid references hq.departments(id),
  financial_year integer not null, amount numeric(18,2) not null check (amount >= 0), currency text not null default 'MZN',
  status text not null default 'draft' check (status in ('draft','submitted','approved','closed')),
  created_by uuid references hq.employees(id), approved_by uuid references hq.employees(id), created_at timestamptz not null default now()
);
create table if not exists hq.profit_distributions (
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  financial_year integer not null, net_profit numeric(18,2) not null, proposed_distribution numeric(18,2) not null,
  retained_earnings numeric(18,2) not null, currency text not null default 'MZN',
  status text not null default 'draft' check (status in ('draft','prepared','under_review','approved','payment_pending','paid','reconciled','rejected')),
  prepared_by uuid references hq.employees(id), reviewed_by uuid references hq.employees(id),
  approval_request_id uuid references hq.approval_requests(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (proposed_distribution >= 0 and retained_earnings >= 0 and proposed_distribution + retained_earnings <= net_profit)
);
create table if not exists hq.profit_distribution_lines (
  id uuid primary key default gen_random_uuid(), distribution_id uuid not null references hq.profit_distributions(id) on delete cascade,
  shareholder_id uuid not null references hq.shareholders(id), quota_percent numeric(5,2) not null,
  amount numeric(18,2) not null, payment_status text not null default 'pending', payment_reference text,
  paid_at timestamptz, unique (distribution_id, shareholder_id)
);
create table if not exists hq.documents (
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  platform_id uuid references hq.platforms(id), category text not null, title text not null,
  confidentiality text not null default 'confidential' check (confidentiality in ('internal','confidential','restricted')),
  storage_key text not null, mime_type text, version integer not null default 1, status text not null default 'active',
  uploaded_by uuid references hq.employees(id), created_at timestamptz not null default now()
);
create table if not exists hq.contracts (
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  platform_id uuid references hq.platforms(id), document_id uuid references hq.documents(id),
  title text not null, counterparty text, owner_employee_id uuid references hq.employees(id),
  status text not null default 'draft' check (status in ('draft','under_review','legal_review','approved','signed','active','expired','terminated')),
  starts_on date, expires_on date, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists hq.hr_records (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references hq.employees(id),
  record_type text not null, status text not null default 'active', starts_on date, ends_on date,
  document_id uuid references hq.documents(id), confidential_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists hq.support_tickets (
  id uuid primary key default gen_random_uuid(), platform_id uuid not null references hq.platforms(id),
  external_reference text, customer_reference text, subject text not null, priority text not null default 'normal',
  status text not null default 'new' check (status in ('new','assigned','in_progress','waiting','resolved','closed')),
  assigned_to uuid references hq.employees(id), opened_at timestamptz not null default now(), resolved_at timestamptz
);
create table if not exists hq.marketing_campaigns (
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id),
  title text not null, status text not null default 'draft' check (status in ('draft','review','approved','published','archived')),
  owner_id uuid references hq.employees(id), starts_at timestamptz, ends_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists hq.campaign_platforms (
  campaign_id uuid not null references hq.marketing_campaigns(id) on delete cascade,
  platform_id uuid not null references hq.platforms(id), primary key (campaign_id, platform_id)
);
create table if not exists hq.field_visits (
  id uuid primary key default gen_random_uuid(), platform_id uuid not null references hq.platforms(id),
  worker_id uuid not null references hq.employees(id), task_id uuid references hq.tasks(id), subject text not null,
  status text not null default 'planned' check (status in ('planned','in_progress','completed','cancelled')),
  planned_at timestamptz, started_at timestamptz, completed_at timestamptz, location jsonb, report text
);
create table if not exists hq.acquisition_leads (
  id uuid primary key default gen_random_uuid(), platform_id uuid not null references hq.platforms(id),
  owner_id uuid references hq.employees(id), name text not null, contact text, stage text not null default 'new',
  status text not null default 'open', next_follow_up_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists hq.ambassadors (
  id uuid primary key default gen_random_uuid(), employee_id uuid references hq.employees(id),
  display_name text not null, status text not null default 'active', joined_at timestamptz not null default now()
);
create table if not exists hq.ambassador_platforms (
  ambassador_id uuid not null references hq.ambassadors(id) on delete cascade,
  platform_id uuid not null references hq.platforms(id), primary key (ambassador_id, platform_id)
);
create index if not exists idx_hq_audit_occurred on hq.audit_logs (occurred_at desc);
create index if not exists idx_hq_activity_employee on hq.employee_activity (employee_id, occurred_at desc);
create index if not exists idx_hq_tasks_assignee_status on hq.tasks (assigned_to, status);
create index if not exists idx_hq_financial_transactions_context on hq.financial_transactions (legal_entity_id, platform_id, occurred_at desc);
create index if not exists idx_hq_support_status on hq.support_tickets (platform_id, status, opened_at desc);
do $$ declare t text; begin
  foreach t in array array['legal_entities','platforms','departments','employees','roles','permissions','employee_roles','role_permissions','employee_platforms','shareholders','ownership_history','approval_requests','approval_decisions','audit_logs','login_sessions','notifications','tasks','employee_activity','financial_accounts','financial_transactions','budgets','profit_distributions','profit_distribution_lines','documents','contracts','hr_records','support_tickets','marketing_campaigns','campaign_platforms','field_visits','acquisition_leads','ambassadors','ambassador_platforms']
  loop execute format('alter table hq.%I enable row level security', t); end loop;
end $$;
insert into hq.legal_entities (id, legal_name, legal_form) values
  ('10000000-0000-0000-0000-000000000001','DeliGo Triunfal, Lda.','SOCIEDADE_POR_QUOTAS')
on conflict (legal_name) do update set legal_form = excluded.legal_form;
insert into hq.platforms (id, legal_entity_id, slug, name, schema_name) values
  ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','deligo','DeliGo','deligo'),
  ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','comunhao','Comunhão','comunhao'),
  ('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','taomoz','TaoMoz','taomoz'),
  ('20000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','sarca','SARCA','sarca')
on conflict (slug) do update set name=excluded.name, schema_name=excluded.schema_name;
insert into hq.departments (id, legal_entity_id, code, name) values
  ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','EXECUTIVE','Direcção Executiva'),
  ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','FINANCE','Finanças'),
  ('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','ACCOUNTING','Contabilidade'),
  ('30000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','OPERATIONS','Operações'),
  ('30000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001','HR','Recursos Humanos'),
  ('30000000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000001','LEGAL','Jurídico'),
  ('30000000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000001','TECHNOLOGY','Tecnologia'),
  ('30000000-0000-0000-0000-000000000008','10000000-0000-0000-0000-000000000001','MARKETING','Marketing'),
  ('30000000-0000-0000-0000-000000000009','10000000-0000-0000-0000-000000000001','FIELD','Field'),
  ('30000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000001','SUPPORT','Apoio ao Cliente'),
  ('30000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000001','ACQUISITION','Aquisição de Parceiros'),
  ('30000000-0000-0000-0000-000000000012','10000000-0000-0000-0000-000000000001','AMBASSADORS','Embaixadores'),
  ('30000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000001','PROCUREMENT','Compras'),
  ('30000000-0000-0000-0000-000000000014','10000000-0000-0000-0000-000000000001','ASSETS','Património')
on conflict (legal_entity_id, code) do update set name=excluded.name;
insert into hq.employees (id, employee_code, legal_entity_id, department_id, display_name, job_title, status) values
  ('40000000-0000-0000-0000-000000000001','DG-0001','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Anwar Abubacar Ismael','CEO e Fundador','active'),
  ('40000000-0000-0000-0000-000000000002','DG-0002','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002','Sara Vitorino Feniosse Ismael','Sócia e Diretora Financeira','active'),
  ('40000000-0000-0000-0000-000000000003','DG-0003','10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000004','Sansão Chume','Supervisor de Operações','active')
on conflict (employee_code) do update set display_name=excluded.display_name, job_title=excluded.job_title, department_id=excluded.department_id;
insert into hq.roles (id, legal_entity_id, code, name, scope, system_role) values
  ('50000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','SUPER_ADMIN','Super Administrador','global',true),
  ('50000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','FINANCE_DIRECTOR','Diretora Financeira','department',true),
  ('50000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','OPERATIONS_SUPERVISOR','Supervisor de Operações','department',true),
  ('50000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','ACCOUNTANT','Contabilista','department',true),
  ('50000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001','HR_MANAGER','Gestor de RH','department',true),
  ('50000000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000001','LEGAL_COUNSEL','Assessor Jurídico','department',true),
  ('50000000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000001','MARKETING','Marketing','platform',true),
  ('50000000-0000-0000-0000-000000000008','10000000-0000-0000-0000-000000000001','FIELD','Field','platform',true),
  ('50000000-0000-0000-0000-000000000009','10000000-0000-0000-0000-000000000001','CUSTOMER_SUPPORT','Apoio ao Cliente','platform',true),
  ('50000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000001','PARTNER_ACQUISITION','Aquisição de Parceiros','platform',true),
  ('50000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000001','AMBASSADOR','Embaixador','platform',true)
on conflict (legal_entity_id, code) do update set name=excluded.name, scope=excluded.scope;
insert into hq.employee_roles (employee_id, role_id, department_id, granted_by) values
  ('40000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001'),
  ('40000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000001'),
  ('40000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000004','40000000-0000-0000-0000-000000000001')
on conflict (employee_id, role_id, department_id, platform_id) do nothing;
insert into hq.shareholders (id, legal_entity_id, employee_id, display_name, quota_percent, effective_from, is_managing_partner) values
  ('60000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','Anwar Abubacar Ismael',50,current_date,true),
  ('60000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002','Sara Vitorino Feniosse Ismael',50,current_date,false)
on conflict (id) do update set quota_percent=excluded.quota_percent, display_name=excluded.display_name;
grant all on all tables in schema hq to service_role;
grant all on all sequences in schema hq to service_role;
commit;
