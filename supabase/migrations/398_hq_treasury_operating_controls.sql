-- Treasury operating layer: reserved purpose, generic payment accounts, budgets,
-- approvals and financial alerts. No provider transfer is executed here.
insert into hq.logical_wallets(wallet_code, wallet_type, currency, metadata)
values
  ('TREASURY_OPERATING_MZN','corporate','MZN','{"purpose":"day-to-day operating treasury"}'),
  ('TAX_OBLIGATIONS_MZN','reserve','MZN','{"purpose":"taxes and statutory obligations"}')
on conflict (wallet_code) do nothing;

create table if not exists hq.payment_accounts (
  id uuid primary key default gen_random_uuid(),
  owner_type text not null check (owner_type in ('corporate','employee','supplier','partner','shareholder')),
  owner_employee_id uuid references hq.employees(id) on delete cascade,
  owner_reference text,
  provider text not null check (provider in ('vodacom_mpesa','movitel','bank','other')),
  account_label text, account_number text not null, masked_number text not null,
  is_verified boolean not null default false, is_primary boolean not null default false,
  status text not null default 'pending' check (status in ('pending','verified','blocked','retired')),
  verified_at timestamptz, verified_by uuid references hq.employees(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (owner_employee_id is not null or owner_reference is not null)
);
create unique index if not exists hq_payment_accounts_primary_owner on hq.payment_accounts(owner_type, coalesce(owner_employee_id::text, owner_reference), provider) where is_primary and status <> 'retired';

create table if not exists hq.department_budgets (
  id uuid primary key default gen_random_uuid(), department_id uuid not null references hq.departments(id) on delete restrict,
  period_start date not null, period_end date not null, amount numeric(18,2) not null check (amount >= 0),
  used_amount numeric(18,2) not null default 0 check (used_amount >= 0), reserved_amount numeric(18,2) not null default 0 check (reserved_amount >= 0),
  status text not null default 'draft' check (status in ('draft','active','closed')),
  created_by uuid references hq.employees(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (period_end >= period_start), unique(department_id, period_start, period_end)
);

create table if not exists hq.finance_approval_items (
  id uuid primary key default gen_random_uuid(), reference_id text not null, operation_type text not null,
  amount numeric(18,2) not null check (amount > 0), status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  required_roles text[] not null default array['FINANCE']::text[], approvals jsonb not null default '[]'::jsonb,
  requested_by uuid references hq.employees(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists hq_finance_approval_items_pending on hq.finance_approval_items(status, created_at desc) where status='pending';

create table if not exists hq.finance_alerts (
  id uuid primary key default gen_random_uuid(), alert_type text not null,
  severity text not null default 'warning' check (severity in ('info','warning','critical')),
  reference_id text, message text not null, status text not null default 'open' check (status in ('open','acknowledged','resolved')),
  created_at timestamptz not null default now(), acknowledged_by uuid references hq.employees(id) on delete set null, resolved_at timestamptz
);

insert into hq.payment_accounts(owner_type, owner_reference, provider, account_label, account_number, masked_number, is_verified, is_primary, status)
values ('corporate','DeliGo Triunfal, Lda','vodacom_mpesa','Referência operacional temporária','8411300015','84•••••15',false,true,'pending')
on conflict do nothing;

alter table hq.payment_accounts enable row level security;
alter table hq.department_budgets enable row level security;
alter table hq.finance_approval_items enable row level security;
alter table hq.finance_alerts enable row level security;
grant select, insert, update on hq.payment_accounts, hq.department_budgets, hq.finance_approval_items, hq.finance_alerts to service_role;

comment on table hq.payment_accounts is 'Generic corporate/person/beneficiary accounts; full numbers are never exposed to unauthorised roles.';
comment on table hq.finance_approval_items is 'Central approval queue for finance and executive dual control.';
comment on table hq.finance_alerts is 'Auditable financial exceptions and reconciliation alerts.';
notify pgrst, 'reload schema';
