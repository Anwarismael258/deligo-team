begin;

create table if not exists hq.payout_requests (
  id uuid primary key default gen_random_uuid(),
  request_type text not null check (request_type in ('withdrawal','refund','user_transfer','bonus','salary')),
  beneficiary_user_id uuid references auth.users(id) on delete set null,
  beneficiary_reference text,
  amount numeric(18,2) not null check (amount > 0),
  currency text not null default 'MZN',
  provider text check (provider is null or provider in ('vodacom_mpesa','movitel')),
  destination_number text,
  status text not null default 'draft' check (status in ('draft','pending_approval','approved','queued','processing','paid','failed','reversed','cancelled')),
  idempotency_key text not null unique,
  source_reference text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  requested_by uuid references hq.employees(id) on delete set null,
  approved_by uuid references hq.employees(id) on delete set null,
  provider_reference text,
  failure_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists hq_payout_requests_status_idx on hq.payout_requests(status, created_at desc);
create index if not exists hq_payout_requests_beneficiary_idx on hq.payout_requests(beneficiary_user_id, created_at desc);

create table if not exists hq.payout_provider_events (
  id uuid primary key default gen_random_uuid(),
  payout_request_id uuid references hq.payout_requests(id) on delete set null,
  provider text not null check (provider in ('vodacom_mpesa','movitel')),
  provider_event_id text not null,
  event_type text not null,
  provider_status text,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  received_at timestamptz not null default now(),
  unique(provider, provider_event_id)
);

create table if not exists hq.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','pending_approval','approved','processing','paid','failed','cancelled')),
  currency text not null default 'MZN',
  total_amount numeric(18,2) not null default 0 check (total_amount >= 0),
  idempotency_key text not null unique,
  prepared_by uuid references hq.employees(id) on delete set null,
  approved_by uuid references hq.employees(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (period_end >= period_start)
);

alter table hq.payout_requests enable row level security;
alter table hq.payout_provider_events enable row level security;
alter table hq.payroll_runs enable row level security;
grant select, insert, update on hq.payout_requests, hq.payout_provider_events, hq.payroll_runs to service_role;

comment on table hq.payout_requests is 'Provider-neutral payout intent. No request is sent externally until an official gateway adapter is configured.';
comment on table hq.payout_provider_events is 'Idempotent Vodacom/Movitel webhook inbox for payout reconciliation.';
comment on table hq.payroll_runs is 'Separate controlled payroll batches for DeliGo Triunfal collaborators.';

notify pgrst, 'reload schema';
commit;
