-- Employee wallet withdrawals through PaySuite.
-- Additive only. Apply after 446 and only in the authorised staging project.
begin;

alter table if exists payments.payout_requests
  add column if not exists provider_reference text,
  add column if not exists idempotency_key text,
  add column if not exists fee_minor bigint not null default 0,
  add column if not exists destination_phone text,
  add column if not exists method text;

create unique index if not exists payments_payout_requests_idempotency_key_uq
  on payments.payout_requests(idempotency_key)
  where idempotency_key is not null;

alter table if exists payments.payout_requests
  drop constraint if exists payout_requests_status_check;
alter table if exists payments.payout_requests
  add constraint payout_requests_status_check
  check (status in ('pending','processing','paid','failed','rejected','cancelled'));

alter table if exists payments.wallet_accounts
  add column if not exists reserved_balance_minor bigint not null default 0;

comment on table payments.payout_requests is
  'PaySuite employee payout requests. The wallet reservation RPC is the only balance mutation path.';

commit;
