begin;

create table if not exists hq.logical_wallets (
  id uuid primary key default gen_random_uuid(),
  wallet_code text not null unique,
  wallet_type text not null check (wallet_type in ('corporate','payroll','expense','settlement','employee','shareholder','reserve')),
  owner_employee_id uuid references hq.employees(id) on delete set null,
  owner_user_id uuid references auth.users(id) on delete set null,
  currency text not null default 'MZN',
  status text not null default 'active' check (status in ('active','blocked','closed')),
  available_amount numeric(18,2) not null default 0 check (available_amount >= 0),
  pending_amount numeric(18,2) not null default 0 check (pending_amount >= 0),
  reserved_amount numeric(18,2) not null default 0 check (reserved_amount >= 0),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists hq.ledger_operations (
  id uuid primary key default gen_random_uuid(),
  wallet_from uuid references hq.logical_wallets(id) on delete restrict,
  wallet_to uuid references hq.logical_wallets(id) on delete restrict,
  amount numeric(18,2) not null check (amount > 0),
  currency text not null default 'MZN',
  operation_type text not null check (operation_type in ('REVENUE','PAYROLL_FUNDING','SALARY_CREDIT','BONUS_CREDIT','EXPENSE_RESERVATION','EXPENSE_PAYMENT','ADVANCE_ISSUED','ADVANCE_SETTLEMENT','ADVANCE_RETURN','PARTNER_SETTLEMENT','EMPLOYEE_WITHDRAWAL','SHAREHOLDER_DISTRIBUTION','INTERNAL_TRANSFER','REFUND','REVERSAL','ADJUSTMENT')),
  reference_id text,
  status text not null default 'pending' check (status in ('pending','approved','queued','processing','available','payable','reserved','settled','failed','reversed','cancelled')),
  requested_by uuid references hq.employees(id) on delete set null,
  approved_by uuid references hq.employees(id) on delete set null,
  executed_by uuid references hq.employees(id) on delete set null,
  provider text check (provider is null or provider in ('vodacom_mpesa','movitel')),
  provider_reference text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  requested_at timestamptz not null default now(), approved_at timestamptz, executed_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists hq_ledger_operations_reference_idx on hq.ledger_operations(reference_id, created_at desc);
create index if not exists hq_ledger_operations_status_idx on hq.ledger_operations(status, created_at desc);

create table if not exists hq.employee_payment_accounts (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references hq.employees(id) on delete cascade,
  provider text not null check (provider in ('vodacom_mpesa','movitel')),
  account_number text not null,
  masked_number text not null,
  is_verified boolean not null default false,
  is_primary boolean not null default false,
  status text not null default 'pending' check (status in ('pending','verified','blocked','retired')),
  verified_at timestamptz, verified_by uuid references hq.employees(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists hq_employee_one_primary_provider on hq.employee_payment_accounts(employee_id, provider) where is_primary and status <> 'retired';

create table if not exists hq.employee_payment_account_changes (
  id uuid primary key default gen_random_uuid(), payment_account_id uuid not null references hq.employee_payment_accounts(id) on delete cascade,
  employee_id uuid not null references hq.employees(id) on delete cascade, old_masked_number text, new_masked_number text not null,
  requested_by uuid references hq.employees(id) on delete set null, approved_by uuid references hq.employees(id) on delete set null,
  reason text, created_at timestamptz not null default now()
);

create table if not exists hq.approval_matrix (
  id uuid primary key default gen_random_uuid(), operation_type text not null,
  minimum_amount numeric(18,2) not null default 0 check (minimum_amount >= 0), maximum_amount numeric(18,2), required_approvers integer not null default 1 check (required_approvers > 0), required_roles text[] not null default array['FINANCE']::text[], is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), check (maximum_amount is null or maximum_amount >= minimum_amount)
);
create index if not exists hq_approval_matrix_lookup on hq.approval_matrix(operation_type, minimum_amount, maximum_amount) where is_active;

create table if not exists hq.employee_advances (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references hq.employees(id) on delete restrict,
  purpose text not null, amount numeric(18,2) not null check (amount > 0), settled_amount numeric(18,2) not null default 0 check (settled_amount >= 0), returned_amount numeric(18,2) not null default 0 check (returned_amount >= 0),
  status text not null default 'requested' check (status in ('requested','approved','issued','accountability_pending','documents_submitted','reconciled','closed','rejected','cancelled')),
  requested_by uuid references hq.employees(id) on delete set null, approved_by uuid references hq.employees(id) on delete set null, due_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists hq_employee_advances_accountability_idx on hq.employee_advances(employee_id, status) where status in ('issued','accountability_pending','documents_submitted');

insert into hq.logical_wallets(wallet_code, wallet_type, currency, metadata) values
  ('CORPORATE_MZN','corporate','MZN','{"purpose":"corporate revenue"}'),
  ('PAYROLL_MZN','payroll','MZN','{"purpose":"reserved payroll"}'),
  ('EXPENSE_MZN','expense','MZN','{"purpose":"approved corporate expenses"}'),
  ('SETTLEMENT_MZN','settlement','MZN','{"purpose":"partner settlements"}')
on conflict (wallet_code) do nothing;

alter table hq.logical_wallets enable row level security;
alter table hq.ledger_operations enable row level security;
alter table hq.employee_payment_accounts enable row level security;
alter table hq.employee_payment_account_changes enable row level security;
alter table hq.approval_matrix enable row level security;
alter table hq.employee_advances enable row level security;
grant select, insert, update on hq.logical_wallets, hq.ledger_operations, hq.employee_payment_accounts, hq.employee_payment_account_changes, hq.approval_matrix, hq.employee_advances to service_role;

comment on table hq.ledger_operations is 'Canonical operation ledger for revenue, payroll, expenses, settlements, refunds and transfers.';
comment on table hq.employee_payment_accounts is 'Verified employee M-Pesa and Movitel accounts; never expose full numbers to unauthorised roles.';
comment on table hq.employee_advances is 'Advances remain outstanding until accountability is reconciled or returned.';

notify pgrst, 'reload schema';
commit;
