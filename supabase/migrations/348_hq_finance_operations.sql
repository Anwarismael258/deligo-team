begin;

alter table hq.financial_accounts
  add column if not exists opening_balance numeric(18,2) not null default 0,
  add column if not exists current_balance numeric(18,2) not null default 0,
  add column if not exists updated_at timestamptz not null default now();

alter table hq.financial_transactions
  add column if not exists description text,
  add column if not exists receipt_path text,
  add column if not exists updated_at timestamptz not null default now();

alter table hq.budgets
  add column if not exists name text,
  add column if not exists spent_amount numeric(18,2) not null default 0 check (spent_amount >= 0),
  add column if not exists period_start date,
  add column if not exists period_end date,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists hq.payment_requests (
  id uuid primary key default gen_random_uuid(),
  legal_entity_id uuid not null references hq.legal_entities(id),
  platform_id uuid references hq.platforms(id),
  payee text not null,
  description text not null,
  amount numeric(18,2) not null check (amount > 0),
  currency text not null default 'MZN',
  due_at timestamptz,
  status text not null default 'pending' check (status in ('pending','approved','paid','rejected','cancelled')),
  receipt_path text,
  requested_by uuid not null references hq.employees(id),
  approved_by uuid references hq.employees(id),
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (requested_by is null or approved_by is null or requested_by <> approved_by)
);

create table if not exists hq.cashflow_forecasts (
  id uuid primary key default gen_random_uuid(),
  legal_entity_id uuid not null references hq.legal_entities(id),
  platform_id uuid references hq.platforms(id),
  period_start date not null,
  period_end date not null,
  expected_income numeric(18,2) not null default 0 check (expected_income >= 0),
  expected_expense numeric(18,2) not null default 0 check (expected_expense >= 0),
  currency text not null default 'MZN',
  created_by uuid references hq.employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (period_end >= period_start)
);

create index if not exists idx_hq_payment_requests_status on hq.payment_requests(status, due_at, created_at desc);
create index if not exists idx_hq_cashflow_forecasts_period on hq.cashflow_forecasts(period_start, period_end, platform_id);
create index if not exists idx_hq_financial_transactions_status on hq.financial_transactions(status, transaction_type, occurred_at desc);

alter table hq.payment_requests enable row level security;
alter table hq.cashflow_forecasts enable row level security;
revoke all on hq.payment_requests, hq.cashflow_forecasts from public, anon, authenticated;
grant all on hq.payment_requests, hq.cashflow_forecasts to service_role;
grant all on all sequences in schema hq to service_role;

commit;
