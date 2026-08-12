begin;
create table if not exists comunhao.subscription_plans (
  code text primary key,
  name text not null,
  description text,
  price_minor bigint not null default 0 check (price_minor >= 0),
  currency_code char(3) not null default 'MZN',
  member_limit integer,
  admin_limit integer,
  billing_cycle_days integer not null default 30,
  features jsonb not null default '[]'::jsonb,
  is_public boolean not null default true,
  is_paid boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists comunhao.church_subscriptions (
  church_id uuid primary key references comunhao.churches(id) on delete cascade,
  plan_code text not null references comunhao.subscription_plans(code),
  status text not null default 'trial'
    check (status in ('trial', 'active', 'grace_period', 'suspended', 'cancelled')),
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  current_period_started_at timestamptz,
  current_period_ends_at timestamptz,
  grace_period_ends_at timestamptz,
  activated_at timestamptz,
  suspended_at timestamptz,
  cancelled_at timestamptz,
  updated_by_user_id uuid references auth.users(id) on delete set null,
  admin_notes text,
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists comunhao.subscription_requests (
  id uuid primary key,
  church_id uuid not null references comunhao.churches(id) on delete cascade,
  requested_plan_code text not null references comunhao.subscription_plans(code),
  requested_by_user_id uuid not null references auth.users(id) on delete restrict,
  reviewed_by_user_id uuid references auth.users(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  review_notes text,
  expected_amount_minor bigint check (expected_amount_minor is null or expected_amount_minor >= 0),
  payment_provider text,
  payer_phone text,
  payment_reference text,
  payment_notes text,
  payment_transaction_id uuid references payments.payment_transactions(id) on delete set null,
  migration_batch text,
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  payment_submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists comunhao.donation_campaigns (
  id uuid primary key,
  church_id uuid not null references comunhao.churches(id) on delete cascade,
  title text not null,
  description text,
  target_amount_minor bigint check (target_amount_minor is null or target_amount_minor >= 0),
  currency_code char(3) not null default 'MZN',
  starts_at timestamptz,
  ends_at timestamptz,
  status text not null default 'active'
    check (status in ('draft', 'active', 'completed', 'cancelled', 'archived')),
  image_url text,
  created_by_user_id uuid references auth.users(id) on delete set null,
  migration_batch text,
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists comunhao.donations (
  id uuid primary key,
  church_id uuid not null references comunhao.churches(id) on delete cascade,
  donor_user_id uuid references auth.users(id) on delete set null,
  legacy_profile_id uuid,
  campaign_id uuid references comunhao.donation_campaigns(id) on delete set null,
  payment_transaction_id uuid references payments.payment_transactions(id) on delete set null,
  amount_minor bigint not null check (amount_minor > 0),
  currency_code char(3) not null default 'MZN',
  contribution_type text,
  payment_method text not null,
  provider text,
  provider_reference text,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'confirmed', 'rejected', 'refunded', 'cancelled')),
  is_recurring boolean not null default false,
  anonymous_donation boolean not null default false,
  public_donation boolean not null default false,
  anonymous_name text,
  proof_url text,
  receipt_number text,
  notes text,
  confirmed_by_user_id uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  migration_batch text,
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists comunhao.finance_receipts (
  id uuid primary key,
  church_id uuid not null references comunhao.churches(id) on delete cascade,
  donation_id uuid not null references comunhao.donations(id) on delete restrict,
  receipt_number text not null unique,
  validation_code text not null unique,
  issued_by_user_id uuid references auth.users(id) on delete set null,
  payload jsonb not null default '{}'::jsonb,
  migration_batch text,
  is_demo boolean not null default false,
  issued_at timestamptz not null default now()
);
create index if not exists idx_comunhao_subscriptions_status on comunhao.church_subscriptions (status);
create index if not exists idx_comunhao_subscription_requests_church on comunhao.subscription_requests (church_id, status);
create index if not exists idx_comunhao_campaigns_church on comunhao.donation_campaigns (church_id, status);
create index if not exists idx_comunhao_donations_church on comunhao.donations (church_id, created_at desc);
create index if not exists idx_comunhao_donations_donor on comunhao.donations (donor_user_id, created_at desc);
create index if not exists idx_comunhao_receipts_church on comunhao.finance_receipts (church_id, issued_at desc);
create unique index if not exists idx_payments_transactions_legacy_source_record
  on payments.payment_transactions (legacy_source, legacy_record_id)
  where legacy_source is not null and legacy_record_id is not null;
create unique index if not exists idx_payments_ledger_comunhao_legacy_id
  on payments.wallet_ledger_entries ((metadata ->> 'legacy_comunhao_ledger_id'))
  where metadata ? 'legacy_comunhao_ledger_id';
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'subscription_plans', 'church_subscriptions', 'subscription_requests',
    'donation_campaigns', 'donations'
  ]
  loop
    execute format('drop trigger if exists %I on comunhao.%I', 'trg_comunhao_' || v_table || '_touch_updated_at', v_table);
    execute format(
      'create trigger %I before update on comunhao.%I for each row execute function public.touch_updated_at()',
      'trg_comunhao_' || v_table || '_touch_updated_at',
      v_table
    );
    execute format('alter table comunhao.%I enable row level security', v_table);
  end loop;
  alter table comunhao.finance_receipts enable row level security;
end;
$$;
drop policy if exists comunhao_subscription_plans_read on comunhao.subscription_plans;
create policy comunhao_subscription_plans_read on comunhao.subscription_plans
for select to authenticated using (is_active);
drop policy if exists comunhao_church_subscriptions_read_member on comunhao.church_subscriptions;
create policy comunhao_church_subscriptions_read_member on comunhao.church_subscriptions
for select to authenticated
using (comunhao.is_church_member(church_id, auth.uid()));
drop policy if exists comunhao_church_subscriptions_manage_admin on comunhao.church_subscriptions;
create policy comunhao_church_subscriptions_manage_admin on comunhao.church_subscriptions
for all to authenticated
using (core.is_platform_admin(auth.uid()))
with check (core.is_platform_admin(auth.uid()));
drop policy if exists comunhao_subscription_requests_read_leader on comunhao.subscription_requests;
create policy comunhao_subscription_requests_read_leader on comunhao.subscription_requests
for select to authenticated
using (
  requested_by_user_id = auth.uid()
  or comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','finance_manager'])
);
drop policy if exists comunhao_subscription_requests_create_leader on comunhao.subscription_requests;
create policy comunhao_subscription_requests_create_leader on comunhao.subscription_requests
for insert to authenticated
with check (
  requested_by_user_id = auth.uid()
  and comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','finance_manager'])
);
drop policy if exists comunhao_campaigns_read_member on comunhao.donation_campaigns;
create policy comunhao_campaigns_read_member on comunhao.donation_campaigns
for select to authenticated
using (comunhao.is_church_member(church_id, auth.uid()));
drop policy if exists comunhao_campaigns_manage_finance on comunhao.donation_campaigns;
create policy comunhao_campaigns_manage_finance on comunhao.donation_campaigns
for all to authenticated
using (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','finance_manager']))
with check (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','finance_manager']));
drop policy if exists comunhao_donations_read_self_or_finance on comunhao.donations;
create policy comunhao_donations_read_self_or_finance on comunhao.donations
for select to authenticated
using (
  donor_user_id = auth.uid()
  or comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','finance_manager','treasurer'])
);
drop policy if exists comunhao_donations_create_self on comunhao.donations;
create policy comunhao_donations_create_self on comunhao.donations
for insert to authenticated
with check (donor_user_id = auth.uid() or donor_user_id is null);
drop policy if exists comunhao_donations_manage_finance on comunhao.donations;
create policy comunhao_donations_manage_finance on comunhao.donations
for update to authenticated
using (comunhao.has_church_role(church_id, auth.uid(), array['pastor','church_admin','organization_admin','finance_manager','treasurer']));
drop policy if exists comunhao_receipts_read_self_or_finance on comunhao.finance_receipts;
create policy comunhao_receipts_read_self_or_finance on comunhao.finance_receipts
for select to authenticated
using (
  exists (
    select 1
    from comunhao.donations d
    where d.id = finance_receipts.donation_id
      and (
        d.donor_user_id = auth.uid()
        or comunhao.has_church_role(d.church_id, auth.uid(), array['pastor','church_admin','organization_admin','finance_manager','treasurer'])
      )
  )
);
drop policy if exists payments_wallet_accounts_select_comunhao_church on payments.wallet_accounts;
create policy payments_wallet_accounts_select_comunhao_church
on payments.wallet_accounts
for select to authenticated
using (
  app_id = (select id from core.apps where slug = 'comunhao')
  and account_type = 'church'
  and metadata ? 'church_id'
  and comunhao.is_church_member((metadata ->> 'church_id')::uuid, auth.uid())
);
drop policy if exists payments_wallet_ledger_select_comunhao_church on payments.wallet_ledger_entries;
create policy payments_wallet_ledger_select_comunhao_church
on payments.wallet_ledger_entries
for select to authenticated
using (
  app_id = (select id from core.apps where slug = 'comunhao')
  and exists (
    select 1
    from payments.wallet_accounts wa
    where wa.id = wallet_ledger_entries.wallet_account_id
      and wa.metadata ? 'church_id'
      and comunhao.has_church_role(
        (wa.metadata ->> 'church_id')::uuid,
        auth.uid(),
        array['pastor','church_admin','organization_admin','finance_manager','treasurer']
      )
  )
);
grant select on
  comunhao.subscription_plans,
  comunhao.church_subscriptions,
  comunhao.subscription_requests,
  comunhao.donation_campaigns,
  comunhao.donations,
  comunhao.finance_receipts
to authenticated;
grant insert on comunhao.subscription_requests, comunhao.donations to authenticated;
grant update on comunhao.donations to authenticated;
grant all privileges on
  comunhao.subscription_plans,
  comunhao.church_subscriptions,
  comunhao.subscription_requests,
  comunhao.donation_campaigns,
  comunhao.donations,
  comunhao.finance_receipts
to service_role;
commit;
