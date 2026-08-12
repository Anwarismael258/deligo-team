-- DeliGo Triunfal Platform
-- Phase 1 blueprint: shared payments and wallet foundation.
-- Additive only. Legacy public wallet and payment tables remain untouched.

begin;
create table if not exists payments.wallet_accounts (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users(id) on delete set null,
  app_id uuid references core.apps(id) on delete set null,
  account_code text unique,
  account_type text not null
    check (account_type in ('user', 'merchant', 'driver', 'church', 'seller', 'platform', 'escrow', 'system')),
  currency_code char(3) not null default 'MZN',
  available_balance_minor bigint not null default 0,
  pending_balance_minor bigint not null default 0,
  status text not null default 'active'
    check (status in ('active', 'suspended', 'closed')),
  legacy_source text,
  legacy_wallet_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table payments.wallet_accounts is 'Canonical wallet accounts shared across products. Cached balances exist for speed; the ledger remains the financial source of truth.';
comment on column payments.wallet_accounts.available_balance_minor is 'Spendable balance cached in minor currency units.';
comment on column payments.wallet_accounts.pending_balance_minor is 'Reserved or pending amount cached in minor currency units.';
create table if not exists payments.idempotency_keys (
  id uuid primary key default gen_random_uuid(),
  app_id uuid references core.apps(id) on delete set null,
  scope_name text not null,
  idempotency_key text not null,
  request_hash text,
  request_payload jsonb,
  response_snapshot jsonb,
  status text not null default 'in_progress'
    check (status in ('in_progress', 'completed', 'failed', 'expired')),
  created_by uuid references auth.users(id) on delete set null,
  locked_at timestamptz,
  finalized_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table payments.idempotency_keys is 'Durable idempotency registry for payment, payout, refund and escrow operations.';
create table if not exists payments.payment_methods (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  app_id uuid references core.apps(id) on delete set null,
  method_type text not null
    check (method_type in ('wallet', 'cash', 'mpesa', 'emola', 'card', 'bank', 'manual')),
  provider text,
  provider_account_ref text,
  masked_label text,
  is_default boolean not null default false,
  status text not null default 'active'
    check (status in ('active', 'inactive', 'revoked')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table payments.payment_methods is 'Stored payment destinations or sources that belong to a user.';
create table if not exists payments.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  app_id uuid references core.apps(id) on delete set null,
  initiator_user_id uuid references auth.users(id) on delete set null,
  wallet_account_id uuid references payments.wallet_accounts(id) on delete set null,
  payment_method_id uuid references payments.payment_methods(id) on delete set null,
  idempotency_key_id uuid references payments.idempotency_keys(id) on delete set null,
  transaction_type text not null
    check (transaction_type in ('topup', 'payment', 'withdrawal', 'transfer', 'commission', 'refund', 'payout', 'escrow_hold', 'escrow_release', 'adjustment')),
  status text not null default 'pending'
    check (status in ('pending', 'authorized', 'processing', 'settled', 'failed', 'cancelled', 'reversed')),
  funds_status text not null default 'none'
    check (funds_status in ('none', 'held_in_escrow', 'released', 'refunded', 'partially_refunded')),
  amount_minor bigint not null check (amount_minor >= 0),
  fee_minor bigint not null default 0 check (fee_minor >= 0),
  provider text,
  provider_reference text,
  external_reference text,
  legacy_source text,
  legacy_record_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  settled_at timestamptz,
  failed_at timestamptz
);
comment on table payments.payment_transactions is 'Canonical payment, top-up, withdrawal and settlement records.';
comment on column payments.payment_transactions.funds_status is 'Separates payment lifecycle from the real money lifecycle to support escrow and delayed settlement.';
create table if not exists payments.escrow_holds (
  id uuid primary key default gen_random_uuid(),
  app_id uuid references core.apps(id) on delete set null,
  source_wallet_account_id uuid not null references payments.wallet_accounts(id) on delete restrict,
  destination_wallet_account_id uuid references payments.wallet_accounts(id) on delete set null,
  payment_transaction_id uuid references payments.payment_transactions(id) on delete set null,
  idempotency_key_id uuid references payments.idempotency_keys(id) on delete set null,
  reference_type text not null,
  reference_id text not null,
  status text not null default 'held'
    check (status in ('held', 'partially_released', 'released', 'captured', 'cancelled', 'expired')),
  amount_minor bigint not null check (amount_minor >= 0),
  released_amount_minor bigint not null default 0 check (released_amount_minor >= 0),
  captured_amount_minor bigint not null default 0 check (captured_amount_minor >= 0),
  metadata jsonb not null default '{}'::jsonb,
  held_at timestamptz not null default now(),
  released_at timestamptz,
  expires_at timestamptz,
  updated_at timestamptz not null default now(),
  check (released_amount_minor + captured_amount_minor <= amount_minor)
);
comment on table payments.escrow_holds is 'Money held between authorization and final settlement. Required for serious multi-product payment flows.';
create table if not exists payments.payout_requests (
  id uuid primary key default gen_random_uuid(),
  app_id uuid references core.apps(id) on delete set null,
  source_wallet_account_id uuid not null references payments.wallet_accounts(id) on delete restrict,
  beneficiary_user_id uuid references auth.users(id) on delete set null,
  destination_payment_method_id uuid references payments.payment_methods(id) on delete set null,
  requested_by uuid not null references auth.users(id) on delete restrict,
  reviewed_by uuid references auth.users(id) on delete set null,
  amount_minor bigint not null check (amount_minor > 0),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'paid', 'rejected', 'cancelled')),
  request_note text,
  rejection_reason text,
  metadata jsonb not null default '{}'::jsonb,
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  paid_at timestamptz,
  updated_at timestamptz not null default now()
);
comment on table payments.payout_requests is 'Withdrawal or settlement requests raised against wallet accounts.';
create table if not exists payments.refunds (
  id uuid primary key default gen_random_uuid(),
  payment_transaction_id uuid not null references payments.payment_transactions(id) on delete cascade,
  app_id uuid references core.apps(id) on delete set null,
  requested_by uuid references auth.users(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  idempotency_key_id uuid references payments.idempotency_keys(id) on delete set null,
  amount_minor bigint not null check (amount_minor > 0),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'refunded', 'rejected', 'failed')),
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  processed_at timestamptz
);
comment on table payments.refunds is 'Refund records kept separate from the original payment transaction for auditability.';
create table if not exists payments.reconciliation_runs (
  id uuid primary key default gen_random_uuid(),
  app_id uuid references core.apps(id) on delete set null,
  scope_name text not null,
  run_date date not null,
  status text not null default 'pending'
    check (status in ('pending', 'running', 'completed', 'failed')),
  mismatch_count integer not null default 0,
  initiated_by uuid references auth.users(id) on delete set null,
  summary jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);
comment on table payments.reconciliation_runs is 'Daily or ad-hoc reconciliation jobs between platform balances and external providers.';
create table if not exists payments.financial_event_groups (
  id uuid primary key default gen_random_uuid(),
  app_id uuid references core.apps(id) on delete set null,
  idempotency_key_id uuid references payments.idempotency_keys(id) on delete set null,
  event_code text not null,
  currency_code char(3) not null default 'MZN',
  reference_type text,
  reference_id text,
  status text not null default 'open'
    check (status in ('open', 'balanced', 'posted', 'reversed')),
  expected_debits_minor bigint not null default 0 check (expected_debits_minor >= 0),
  expected_credits_minor bigint not null default 0 check (expected_credits_minor >= 0),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  posted_at timestamptz
);
comment on table payments.financial_event_groups is 'Explicit balancing groups for double-entry financial events.';
create table if not exists payments.wallet_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  wallet_account_id uuid not null references payments.wallet_accounts(id) on delete restrict,
  app_id uuid references core.apps(id) on delete set null,
  event_group_id uuid references payments.financial_event_groups(id) on delete set null,
  idempotency_key_id uuid references payments.idempotency_keys(id) on delete set null,
  payment_transaction_id uuid references payments.payment_transactions(id) on delete set null,
  escrow_hold_id uuid references payments.escrow_holds(id) on delete set null,
  counterparty_wallet_account_id uuid references payments.wallet_accounts(id) on delete set null,
  entry_side text not null check (entry_side in ('debit', 'credit')),
  entry_type text not null,
  currency_code char(3) not null default 'MZN',
  amount_minor bigint not null check (amount_minor > 0),
  balance_after_minor bigint,
  reference_type text,
  reference_id text,
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
comment on table payments.wallet_ledger_entries is 'Append-only financial ledger. This is the canonical accounting trail and must never be updated or deleted in normal operations.';
comment on column payments.wallet_ledger_entries.event_group_id is 'Shared identifier used to balance related debits and credits across a single financial event.';
create index if not exists idx_payments_wallet_accounts_owner on payments.wallet_accounts (owner_user_id, status);
create index if not exists idx_payments_wallet_accounts_app on payments.wallet_accounts (app_id, account_type);
create unique index if not exists idx_payments_wallet_accounts_scoped_owner
  on payments.wallet_accounts (owner_user_id, app_id, account_type, currency_code)
  where owner_user_id is not null and app_id is not null;
create unique index if not exists idx_payments_wallet_accounts_global_owner
  on payments.wallet_accounts (owner_user_id, account_type, currency_code)
  where owner_user_id is not null and app_id is null;
create index if not exists idx_payments_idempotency_keys_scope on payments.idempotency_keys (scope_name, status);
create unique index if not exists idx_payments_idempotency_keys_scoped
  on payments.idempotency_keys (app_id, scope_name, idempotency_key)
  where app_id is not null;
create unique index if not exists idx_payments_idempotency_keys_global
  on payments.idempotency_keys (scope_name, idempotency_key)
  where app_id is null;
create index if not exists idx_payments_payment_methods_owner on payments.payment_methods (owner_user_id, status);
create unique index if not exists idx_payments_provider_reference
  on payments.payment_transactions (provider, provider_reference)
  where provider_reference is not null;
create index if not exists idx_payments_transactions_wallet on payments.payment_transactions (wallet_account_id, status, created_at desc);
create index if not exists idx_payments_transactions_initiator on payments.payment_transactions (initiator_user_id, created_at desc);
create index if not exists idx_payments_escrow_reference on payments.escrow_holds (reference_type, reference_id, status);
create index if not exists idx_payments_payouts_wallet on payments.payout_requests (source_wallet_account_id, status, requested_at desc);
create index if not exists idx_payments_refunds_payment on payments.refunds (payment_transaction_id, status, created_at desc);
create index if not exists idx_payments_reconciliation_scope on payments.reconciliation_runs (scope_name, run_date desc);
create unique index if not exists idx_payments_reconciliation_runs_scoped
  on payments.reconciliation_runs (app_id, scope_name, run_date)
  where app_id is not null;
create unique index if not exists idx_payments_reconciliation_runs_global
  on payments.reconciliation_runs (scope_name, run_date)
  where app_id is null;
create index if not exists idx_payments_financial_event_groups_reference
  on payments.financial_event_groups (app_id, event_code, reference_type, reference_id);
create index if not exists idx_payments_wallet_ledger_wallet on payments.wallet_ledger_entries (wallet_account_id, created_at desc);
create index if not exists idx_payments_wallet_ledger_group on payments.wallet_ledger_entries (event_group_id);
create index if not exists idx_payments_wallet_ledger_payment on payments.wallet_ledger_entries (payment_transaction_id);
create or replace function payments.is_wallet_owner(p_wallet_account_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = payments, public
as $$
  select exists (
    select 1
    from payments.wallet_accounts wa
    where wa.id = p_wallet_account_id
      and wa.owner_user_id = p_user_id
  );
$$;
create or replace function payments.is_payment_method_owner(p_payment_method_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = payments, public
as $$
  select exists (
    select 1
    from payments.payment_methods pm
    where pm.id = p_payment_method_id
      and pm.owner_user_id = p_user_id
  );
$$;
create or replace function payments.prevent_wallet_ledger_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'payments.wallet_ledger_entries is append-only; create compensating entries instead of updating or deleting existing rows.';
end;
$$;
drop trigger if exists trg_payments_wallet_accounts_touch_updated_at on payments.wallet_accounts;
create trigger trg_payments_wallet_accounts_touch_updated_at
before update on payments.wallet_accounts
for each row execute function public.touch_updated_at();
drop trigger if exists trg_payments_idempotency_keys_touch_updated_at on payments.idempotency_keys;
create trigger trg_payments_idempotency_keys_touch_updated_at
before update on payments.idempotency_keys
for each row execute function public.touch_updated_at();
drop trigger if exists trg_payments_payment_methods_touch_updated_at on payments.payment_methods;
create trigger trg_payments_payment_methods_touch_updated_at
before update on payments.payment_methods
for each row execute function public.touch_updated_at();
drop trigger if exists trg_payments_payment_transactions_touch_updated_at on payments.payment_transactions;
create trigger trg_payments_payment_transactions_touch_updated_at
before update on payments.payment_transactions
for each row execute function public.touch_updated_at();
drop trigger if exists trg_payments_escrow_holds_touch_updated_at on payments.escrow_holds;
create trigger trg_payments_escrow_holds_touch_updated_at
before update on payments.escrow_holds
for each row execute function public.touch_updated_at();
drop trigger if exists trg_payments_payout_requests_touch_updated_at on payments.payout_requests;
create trigger trg_payments_payout_requests_touch_updated_at
before update on payments.payout_requests
for each row execute function public.touch_updated_at();
drop trigger if exists trg_payments_refunds_touch_updated_at on payments.refunds;
create trigger trg_payments_refunds_touch_updated_at
before update on payments.refunds
for each row execute function public.touch_updated_at();
drop trigger if exists trg_payments_reconciliation_runs_touch_updated_at on payments.reconciliation_runs;
create trigger trg_payments_reconciliation_runs_touch_updated_at
before update on payments.reconciliation_runs
for each row execute function public.touch_updated_at();
drop trigger if exists trg_payments_financial_event_groups_touch_updated_at on payments.financial_event_groups;
create trigger trg_payments_financial_event_groups_touch_updated_at
before update on payments.financial_event_groups
for each row execute function public.touch_updated_at();
drop trigger if exists trg_payments_wallet_ledger_entries_block_update on payments.wallet_ledger_entries;
create trigger trg_payments_wallet_ledger_entries_block_update
before update on payments.wallet_ledger_entries
for each row execute function payments.prevent_wallet_ledger_mutation();
drop trigger if exists trg_payments_wallet_ledger_entries_block_delete on payments.wallet_ledger_entries;
create trigger trg_payments_wallet_ledger_entries_block_delete
before delete on payments.wallet_ledger_entries
for each row execute function payments.prevent_wallet_ledger_mutation();
alter table payments.wallet_accounts enable row level security;
alter table payments.idempotency_keys enable row level security;
alter table payments.payment_methods enable row level security;
alter table payments.payment_transactions enable row level security;
alter table payments.escrow_holds enable row level security;
alter table payments.payout_requests enable row level security;
alter table payments.refunds enable row level security;
alter table payments.reconciliation_runs enable row level security;
alter table payments.financial_event_groups enable row level security;
alter table payments.wallet_ledger_entries enable row level security;
drop policy if exists payments_wallet_accounts_select_owner_or_admin on payments.wallet_accounts;
create policy payments_wallet_accounts_select_owner_or_admin
on payments.wallet_accounts
for select
to authenticated
using (
  owner_user_id = auth.uid()
  or core.is_platform_admin(auth.uid())
);
drop policy if exists payments_payment_methods_select_owner_or_admin on payments.payment_methods;
create policy payments_payment_methods_select_owner_or_admin
on payments.payment_methods
for select
to authenticated
using (
  owner_user_id = auth.uid()
  or core.is_platform_admin(auth.uid())
);
drop policy if exists payments_payment_methods_insert_owner_or_admin on payments.payment_methods;
create policy payments_payment_methods_insert_owner_or_admin
on payments.payment_methods
for insert
to authenticated
with check (
  owner_user_id = auth.uid()
  or core.is_platform_admin(auth.uid())
);
drop policy if exists payments_payment_methods_update_owner_or_admin on payments.payment_methods;
create policy payments_payment_methods_update_owner_or_admin
on payments.payment_methods
for update
to authenticated
using (
  owner_user_id = auth.uid()
  or core.is_platform_admin(auth.uid())
)
with check (
  owner_user_id = auth.uid()
  or core.is_platform_admin(auth.uid())
);
drop policy if exists payments_payment_methods_delete_owner_or_admin on payments.payment_methods;
create policy payments_payment_methods_delete_owner_or_admin
on payments.payment_methods
for delete
to authenticated
using (
  owner_user_id = auth.uid()
  or core.is_platform_admin(auth.uid())
);
drop policy if exists payments_payment_transactions_select_owner_or_admin on payments.payment_transactions;
create policy payments_payment_transactions_select_owner_or_admin
on payments.payment_transactions
for select
to authenticated
using (
  initiator_user_id = auth.uid()
  or payments.is_wallet_owner(wallet_account_id, auth.uid())
  or core.is_platform_admin(auth.uid())
);
drop policy if exists payments_escrow_holds_select_owner_or_admin on payments.escrow_holds;
create policy payments_escrow_holds_select_owner_or_admin
on payments.escrow_holds
for select
to authenticated
using (
  payments.is_wallet_owner(source_wallet_account_id, auth.uid())
  or payments.is_wallet_owner(destination_wallet_account_id, auth.uid())
  or core.is_platform_admin(auth.uid())
);
drop policy if exists payments_payout_requests_select_owner_or_admin on payments.payout_requests;
create policy payments_payout_requests_select_owner_or_admin
on payments.payout_requests
for select
to authenticated
using (
  requested_by = auth.uid()
  or beneficiary_user_id = auth.uid()
  or payments.is_wallet_owner(source_wallet_account_id, auth.uid())
  or core.is_platform_admin(auth.uid())
);
drop policy if exists payments_payout_requests_insert_owner_or_admin on payments.payout_requests;
create policy payments_payout_requests_insert_owner_or_admin
on payments.payout_requests
for insert
to authenticated
with check (
  (
    requested_by = auth.uid()
    and payments.is_wallet_owner(source_wallet_account_id, auth.uid())
  )
  or core.is_platform_admin(auth.uid())
);
drop policy if exists payments_payout_requests_update_admin_only on payments.payout_requests;
create policy payments_payout_requests_update_admin_only
on payments.payout_requests
for update
to authenticated
using (core.is_platform_admin(auth.uid()))
with check (core.is_platform_admin(auth.uid()));
drop policy if exists payments_refunds_select_owner_or_admin on payments.refunds;
create policy payments_refunds_select_owner_or_admin
on payments.refunds
for select
to authenticated
using (
  requested_by = auth.uid()
  or exists (
    select 1
    from payments.payment_transactions pt
    where pt.id = payments.refunds.payment_transaction_id
      and (
        pt.initiator_user_id = auth.uid()
        or payments.is_wallet_owner(pt.wallet_account_id, auth.uid())
      )
  )
  or core.is_platform_admin(auth.uid())
);
drop policy if exists payments_refunds_insert_owner_or_admin on payments.refunds;
create policy payments_refunds_insert_owner_or_admin
on payments.refunds
for insert
to authenticated
with check (
  requested_by = auth.uid()
  or core.is_platform_admin(auth.uid())
);
drop policy if exists payments_refunds_update_admin_only on payments.refunds;
create policy payments_refunds_update_admin_only
on payments.refunds
for update
to authenticated
using (core.is_platform_admin(auth.uid()))
with check (core.is_platform_admin(auth.uid()));
drop policy if exists payments_reconciliation_runs_select_auditor_or_admin on payments.reconciliation_runs;
create policy payments_reconciliation_runs_select_auditor_or_admin
on payments.reconciliation_runs
for select
to authenticated
using (core.is_platform_auditor(auth.uid()));
drop policy if exists payments_financial_event_groups_select_auditor_or_admin on payments.financial_event_groups;
create policy payments_financial_event_groups_select_auditor_or_admin
on payments.financial_event_groups
for select
to authenticated
using (core.is_platform_auditor(auth.uid()));
drop policy if exists payments_wallet_ledger_entries_select_owner_or_admin on payments.wallet_ledger_entries;
create policy payments_wallet_ledger_entries_select_owner_or_admin
on payments.wallet_ledger_entries
for select
to authenticated
using (
  payments.is_wallet_owner(wallet_account_id, auth.uid())
  or payments.is_wallet_owner(counterparty_wallet_account_id, auth.uid())
  or core.is_platform_admin(auth.uid())
);
grant select on payments.wallet_accounts, payments.payment_transactions, payments.escrow_holds, payments.refunds, payments.reconciliation_runs, payments.wallet_ledger_entries to authenticated;
grant select on payments.financial_event_groups to authenticated;
grant select, insert, update, delete on payments.payment_methods to authenticated;
grant select, insert, update on payments.payout_requests to authenticated;
grant select, insert, update on payments.refunds to authenticated;
grant all privileges on all tables in schema payments to service_role;
grant execute on function payments.is_wallet_owner(uuid, uuid) to authenticated, service_role;
grant execute on function payments.is_payment_method_owner(uuid, uuid) to authenticated, service_role;
grant execute on function payments.prevent_wallet_ledger_mutation() to service_role;
commit;
