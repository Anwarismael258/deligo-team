begin;

-- Canonical corporate destination for HQ-owned profit. This is a routing
-- record for reconciliation; it does not execute a provider transfer.
create table if not exists hq.corporate_profit_destinations (
  id uuid primary key default gen_random_uuid(),
  destination_type text not null check (destination_type in ('mobile_wallet','bank_account')),
  destination_number text not null,
  currency text not null default 'MZN',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists hq_one_active_profit_destination
  on hq.corporate_profit_destinations (is_active)
  where is_active;

alter table hq.corporate_profit_destinations enable row level security;
grant select, insert, update, delete on hq.corporate_profit_destinations to service_role;

insert into hq.corporate_profit_destinations
  (destination_type, destination_number, currency, metadata)
values
  ('mobile_wallet', '8411300015', 'MZN',
   jsonb_build_object('owner_role', 'SUPER_ADMIN', 'purpose', 'hq_profit_destination', 'provider_transfer_required', true))
on conflict (is_active) where is_active do update set
  destination_type = excluded.destination_type,
  destination_number = excluded.destination_number,
  currency = excluded.currency,
  metadata = excluded.metadata,
  updated_at = now();

create or replace view hq.confirmed_profit_destination_v1 as
select
  d.destination_type,
  d.destination_number,
  d.currency,
  d.metadata,
  coalesce(sum(case when e.payment_status = 'confirmed' then e.platform_fee else 0 end), 0)::numeric(18,2) as confirmed_hq_profit,
  count(e.id) filter (where e.payment_status = 'confirmed') as confirmed_event_count
from hq.corporate_profit_destinations d
left join hq.platform_financial_events e on e.platform_fee > 0
where d.is_active
group by d.destination_type, d.destination_number, d.currency, d.metadata;

comment on table hq.corporate_profit_destinations is
  'Canonical destination for HQ-owned profit reconciliation. Provider settlement remains explicit and auditable.';

notify pgrst, 'reload schema';
commit;
