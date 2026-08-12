begin;

-- One provider registry for every product. Secret values never live here:
-- only a vault reference may be recorded after official onboarding.
create table if not exists payments.provider_configurations (
  provider_slug text primary key check (provider_slug in ('mpesa', 'emola', 'movitel')),
  display_name text not null,
  provider_type text not null default 'mobile_money' check (provider_type in ('mobile_money', 'bank', 'card', 'wallet')),
  connection_status text not null default 'pending_official_api'
    check (connection_status in ('pending_official_api', 'sandbox', 'live', 'suspended', 'retired')),
  webhook_status text not null default 'not_configured'
    check (webhook_status in ('not_configured', 'pending_validation', 'active', 'failed', 'disabled')),
  credentials_reference text,
  supported_app_slugs text[] not null default array['deligo', 'sarca', 'taomoz', 'comunhao', 'mestre24'],
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into payments.provider_configurations(provider_slug, display_name, supported_app_slugs)
values
  ('mpesa', 'M-Pesa', array['deligo', 'sarca', 'taomoz', 'comunhao', 'mestre24']),
  ('emola', 'E-Mola', array['deligo', 'sarca', 'taomoz', 'comunhao', 'mestre24']),
  ('movitel', 'Movitel Money', array['deligo', 'sarca', 'taomoz', 'comunhao', 'mestre24'])
on conflict (provider_slug) do update set
  display_name = excluded.display_name,
  supported_app_slugs = excluded.supported_app_slugs,
  updated_at = now();

-- Canonical intent, created before a provider call exists. A status can only
-- reach confirmed after a future verified provider webhook/settlement flow.
create table if not exists payments.payment_intents (
  id uuid primary key default gen_random_uuid(),
  app_id uuid not null references core.apps(id) on delete restrict,
  payer_user_id uuid references auth.users(id) on delete set null,
  provider_slug text not null references payments.provider_configurations(provider_slug),
  idempotency_key text not null,
  reference_type text not null,
  reference_id text not null,
  amount_minor bigint not null check (amount_minor > 0),
  currency_code char(3) not null default 'MZN',
  status text not null default 'draft'
    check (status in ('draft', 'pending_provider', 'awaiting_customer', 'confirmed', 'failed', 'cancelled', 'expired')),
  provider_reference text,
  expires_at timestamptz,
  confirmed_at timestamptz,
  failed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (app_id, idempotency_key),
  unique (provider_slug, provider_reference)
);

create index if not exists payments_payment_intents_app_status_idx
  on payments.payment_intents(app_id, status, created_at desc);
create index if not exists payments_payment_intents_reference_idx
  on payments.payment_intents(reference_type, reference_id, created_at desc);

alter table payments.provider_configurations enable row level security;
alter table payments.payment_intents enable row level security;
revoke all on payments.provider_configurations, payments.payment_intents from anon, authenticated;
grant all privileges on payments.provider_configurations, payments.payment_intents to service_role;

create or replace function public.group_payment_provider_readiness_v1(p_app_slug text)
returns table (
  provider_slug text,
  display_name text,
  connection_status text,
  webhook_status text,
  ready_for_transactions boolean
)
language sql stable security definer set search_path = payments, core, public, pg_temp as $$
  select pc.provider_slug, pc.display_name, pc.connection_status, pc.webhook_status,
         (pc.connection_status = 'live' and pc.webhook_status = 'active')
  from payments.provider_configurations pc
  where p_app_slug = any(pc.supported_app_slugs)
  order by pc.display_name;
$$;
revoke all on function public.group_payment_provider_readiness_v1(text) from public;
grant execute on function public.group_payment_provider_readiness_v1(text) to authenticated, service_role;

commit;
