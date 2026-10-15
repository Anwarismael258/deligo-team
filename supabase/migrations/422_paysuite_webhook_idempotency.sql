-- PaySuite event inbox. It is append-only and does not mutate balances.
begin;
create schema if not exists payments;
create table if not exists payments.paysuite_webhook_events (
  id bigint generated always as identity primary key,
  provider_event_id text not null,
  event_name text not null,
  reference text,
  payload jsonb not null,
  signature_verified boolean not null default true,
  processing_status text not null default 'received' check (processing_status in ('received','processed','ignored','failed')),
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  error_message text,
  unique (provider_event_id, event_name)
);
alter table payments.paysuite_webhook_events enable row level security;
revoke all on payments.paysuite_webhook_events from public, anon, authenticated;
grant select, insert, update on payments.paysuite_webhook_events to service_role;
commit;
