-- Production contract for PaySuite and real-money reconciliation.
-- Additive only: no balances, ledger history or existing rows are reset.
begin;

alter table if exists payments.provider_configurations
  drop constraint if exists provider_configurations_provider_slug_check;
alter table if exists payments.provider_configurations
  add constraint provider_configurations_provider_slug_check
  check (provider_slug in ('paysuite', 'mpesa', 'emola', 'movitel'));
alter table if exists payments.provider_configurations
  add column if not exists payin_fee_rate numeric(8,6) not null default 0,
  add column if not exists payout_fee_rate numeric(8,6) not null default 0,
  add column if not exists enabled boolean not null default false,
  add column if not exists environment text not null default 'sandbox'
    check (environment in ('sandbox','production'));

insert into payments.provider_configurations
  (provider_slug, display_name, provider_type, connection_status, webhook_status,
   supported_app_slugs, enabled, environment)
values
  ('paysuite', 'PaySuite', 'wallet', 'sandbox', 'pending_validation',
   array['deligo','sarca','taomoz','comunhao','mestre24'], false, 'sandbox')
on conflict (provider_slug) do update set
  display_name = excluded.display_name,
  updated_at = now();

alter table if exists payments.payment_transactions
  add column if not exists reference text,
  add column if not exists method text,
  add column if not exists platform_slug text;

alter table if exists payments.paysuite_webhook_events
  add column if not exists payload_hash text,
  add column if not exists status text;

create unique index if not exists paysuite_webhook_events_provider_hash_uq
  on payments.paysuite_webhook_events(provider_event_id, coalesce(payload_hash, ''));
create index if not exists payment_transactions_provider_reference_idx
  on payments.payment_transactions(provider, provider_reference);

comment on column payments.provider_configurations.credentials_reference is
  'Vault/environment reference only; never store a PaySuite token or secret here.';
comment on column payments.paysuite_webhook_events.payload_hash is
  'Canonical payload digest used with provider_event_id for webhook idempotency.';

commit;
