begin;
create table if not exists taomoz.order_beneficiary_splits (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references taomoz.orders(id) on delete cascade,
  beneficiary_type text not null check (beneficiary_type in ('seller','courier','platform')),
  beneficiary_user_id uuid references auth.users(id) on delete set null,
  wallet_account_id uuid references payments.wallet_accounts(id) on delete set null,
  amount_minor bigint not null check (amount_minor >= 0),
  status text not null default 'pending'
    check (status in ('pending','held','released','paid','refunded','cancelled')),
  migration_batch text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (order_id, beneficiary_type)
);
create index if not exists idx_taomoz_order_splits_beneficiary
  on taomoz.order_beneficiary_splits (beneficiary_user_id, status);
create index if not exists idx_taomoz_order_splits_wallet
  on taomoz.order_beneficiary_splits (wallet_account_id, status);
create unique index if not exists idx_payments_transactions_taomoz_legacy_id
  on payments.payment_transactions ((metadata ->> 'legacy_taomoz_transaction_id'))
  where metadata ? 'legacy_taomoz_transaction_id';
create unique index if not exists idx_payments_escrow_taomoz_order
  on payments.escrow_holds (app_id, reference_type, reference_id)
  where reference_type = 'taomoz_order';
create or replace function taomoz.calculate_order_financials()
returns trigger
language plpgsql
as $$
begin
  new.product_fee_rate_bps := 600;
  new.delivery_fee_rate_bps := 500;
  new.product_commission_minor :=
    round(new.subtotal_minor * new.product_fee_rate_bps / 10000.0)::bigint;
  new.delivery_commission_minor :=
    round(new.delivery_fee_minor * new.delivery_fee_rate_bps / 10000.0)::bigint;
  new.seller_payout_minor := new.subtotal_minor - new.product_commission_minor;
  new.courier_payout_minor := new.delivery_fee_minor - new.delivery_commission_minor;
  new.platform_revenue_minor :=
    new.product_commission_minor + new.delivery_commission_minor;
  new.grand_total_minor := new.subtotal_minor + new.delivery_fee_minor;
  return new;
end;
$$;
drop trigger if exists trg_taomoz_orders_calculate_financials on taomoz.orders;
create trigger trg_taomoz_orders_calculate_financials
before insert or update of subtotal_minor, delivery_fee_minor
on taomoz.orders
for each row execute function taomoz.calculate_order_financials();
create or replace function taomoz.protect_order_financials()
returns trigger
language plpgsql
as $$
begin
  -- Direct API writes execute as authenticated; security-definer backend functions do not.
  if current_user = 'authenticated' and not core.is_platform_admin(auth.uid()) then
    if new.payment_transaction_id is distinct from old.payment_transaction_id
      or new.payment_status is distinct from old.payment_status
      or new.funds_status is distinct from old.funds_status
      or new.subtotal_minor is distinct from old.subtotal_minor
      or new.delivery_fee_minor is distinct from old.delivery_fee_minor
      or new.product_fee_rate_bps is distinct from old.product_fee_rate_bps
      or new.delivery_fee_rate_bps is distinct from old.delivery_fee_rate_bps
      or new.product_commission_minor is distinct from old.product_commission_minor
      or new.delivery_commission_minor is distinct from old.delivery_commission_minor
      or new.seller_payout_minor is distinct from old.seller_payout_minor
      or new.courier_payout_minor is distinct from old.courier_payout_minor
      or new.platform_revenue_minor is distinct from old.platform_revenue_minor
      or new.grand_total_minor is distinct from old.grand_total_minor
      or new.settled_at is distinct from old.settled_at then
      raise exception 'Tao Moz financial fields can only be changed by the trusted backend';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_taomoz_orders_protect_financials on taomoz.orders;
create trigger trg_taomoz_orders_protect_financials
before update on taomoz.orders
for each row execute function taomoz.protect_order_financials();
create or replace function taomoz.sync_order_beneficiary_splits(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = taomoz, payments, core, public
as $$
declare
  v_order taomoz.orders%rowtype;
  v_seller_user_id uuid;
  v_courier_user_id uuid;
  v_app_id uuid;
  v_seller_wallet uuid;
  v_courier_wallet uuid;
  v_platform_wallet uuid;
begin
  select * into strict v_order from taomoz.orders where id=p_order_id;
  select user_id into v_seller_user_id from taomoz.seller_profiles where id=v_order.seller_id;
  select user_id into v_courier_user_id from taomoz.courier_profiles where id=v_order.courier_id;
  select id into strict v_app_id from core.apps where slug='taomoz';

  insert into payments.wallet_accounts (
    owner_user_id,app_id,account_code,account_type,currency_code,metadata
  ) values (
    v_seller_user_id,v_app_id,'taomoz:seller:'||v_seller_user_id,'seller',
    v_order.currency_code,'{"managed_by":"taomoz"}'::jsonb
  )
  on conflict (owner_user_id,app_id,account_type,currency_code)
    where owner_user_id is not null and app_id is not null
  do update set status='active'
  returning id into v_seller_wallet;

  if v_courier_user_id is not null then
    insert into payments.wallet_accounts (
      owner_user_id,app_id,account_code,account_type,currency_code,metadata
    ) values (
      v_courier_user_id,v_app_id,'taomoz:courier:'||v_courier_user_id,'driver',
      v_order.currency_code,'{"managed_by":"taomoz"}'::jsonb
    )
    on conflict (owner_user_id,app_id,account_type,currency_code)
      where owner_user_id is not null and app_id is not null
    do update set status='active'
    returning id into v_courier_wallet;
  end if;

  insert into payments.wallet_accounts (
    app_id,account_code,account_type,currency_code,metadata
  ) values (
    v_app_id,'taomoz:platform:'||v_order.currency_code,'platform',
    v_order.currency_code,'{"managed_by":"taomoz"}'::jsonb
  )
  on conflict (account_code) do update set status='active'
  returning id into v_platform_wallet;

  insert into taomoz.order_beneficiary_splits (
    order_id,beneficiary_type,beneficiary_user_id,wallet_account_id,amount_minor,metadata
  ) values
    (v_order.id,'seller',v_seller_user_id,v_seller_wallet,v_order.seller_payout_minor,'{}'),
    (v_order.id,'platform',null,v_platform_wallet,v_order.platform_revenue_minor,'{}')
  on conflict(order_id,beneficiary_type) do update set
    beneficiary_user_id=excluded.beneficiary_user_id,
    wallet_account_id=excluded.wallet_account_id,
    amount_minor=excluded.amount_minor,
    updated_at=now();

  if v_courier_user_id is not null then
    insert into taomoz.order_beneficiary_splits (
      order_id,beneficiary_type,beneficiary_user_id,wallet_account_id,amount_minor,metadata
    ) values (
      v_order.id,'courier',v_courier_user_id,v_courier_wallet,v_order.courier_payout_minor,'{}'
    )
    on conflict(order_id,beneficiary_type) do update set
      beneficiary_user_id=excluded.beneficiary_user_id,
      wallet_account_id=excluded.wallet_account_id,
      amount_minor=excluded.amount_minor,
      updated_at=now();
  end if;
end;
$$;
create or replace function taomoz.create_order_escrow(
  p_order_id uuid,
  p_source_wallet_account_id uuid,
  p_payment_transaction_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = taomoz, payments, core, public
as $$
declare
  v_order taomoz.orders%rowtype;
  v_app_id uuid;
  v_escrow_wallet_id uuid;
  v_hold_id uuid;
begin
  select * into strict v_order from taomoz.orders where id=p_order_id for update;
  select id into strict v_app_id from core.apps where slug='taomoz';

  if v_order.buyer_user_id <> auth.uid() and auth.uid() is not null
    and not core.is_platform_admin(auth.uid()) then
    raise exception 'Only the buyer or trusted backend can fund this order';
  end if;

  insert into payments.wallet_accounts (
    app_id,account_code,account_type,currency_code,metadata
  ) values (
    v_app_id,'taomoz:escrow:'||v_order.id,'escrow',v_order.currency_code,
    jsonb_build_object('taomoz_order_id',v_order.id)
  )
  on conflict(account_code) do update set status='active'
  returning id into v_escrow_wallet_id;

  insert into payments.escrow_holds (
    app_id,source_wallet_account_id,destination_wallet_account_id,
    payment_transaction_id,reference_type,reference_id,status,amount_minor,metadata
  ) values (
    v_app_id,p_source_wallet_account_id,v_escrow_wallet_id,
    p_payment_transaction_id,'taomoz_order',v_order.id::text,'held',
    v_order.grand_total_minor,jsonb_build_object('taomoz_order_id',v_order.id)
  )
  on conflict(app_id,reference_type,reference_id) where reference_type='taomoz_order'
  do update set payment_transaction_id=excluded.payment_transaction_id,
    source_wallet_account_id=excluded.source_wallet_account_id,
    destination_wallet_account_id=excluded.destination_wallet_account_id,
    amount_minor=excluded.amount_minor,updated_at=now()
  returning id into v_hold_id;

  update taomoz.orders set
    payment_transaction_id=p_payment_transaction_id,
    payment_status='authorized',
    funds_status='held_in_escrow'
  where id=v_order.id;

  perform taomoz.sync_order_beneficiary_splits(v_order.id);
  update taomoz.order_beneficiary_splits set status='held' where order_id=v_order.id;
  return v_hold_id;
end;
$$;
drop trigger if exists trg_taomoz_order_splits_touch_updated_at on taomoz.order_beneficiary_splits;
create trigger trg_taomoz_order_splits_touch_updated_at
before update on taomoz.order_beneficiary_splits
for each row execute function public.touch_updated_at();
alter table taomoz.order_beneficiary_splits enable row level security;
drop policy if exists taomoz_order_splits_read_party on taomoz.order_beneficiary_splits;
create policy taomoz_order_splits_read_party on taomoz.order_beneficiary_splits
for select to authenticated
using (
  beneficiary_user_id=auth.uid()
  or taomoz.is_order_party(order_id,auth.uid())
  or core.is_platform_admin(auth.uid())
);
drop policy if exists payments_transactions_select_taomoz_order_party on payments.payment_transactions;
create policy payments_transactions_select_taomoz_order_party
on payments.payment_transactions for select to authenticated
using (
  app_id=(select id from core.apps where slug='taomoz')
  and metadata ? 'taomoz_order_id'
  and taomoz.is_order_party((metadata->>'taomoz_order_id')::uuid,auth.uid())
);
drop policy if exists payments_escrow_select_taomoz_order_party on payments.escrow_holds;
create policy payments_escrow_select_taomoz_order_party
on payments.escrow_holds for select to authenticated
using (
  reference_type='taomoz_order'
  and taomoz.is_order_party(reference_id::uuid,auth.uid())
);
create or replace view taomoz.order_financial_summary
with (security_invoker=true)
as
select
  o.id order_id,o.order_number,o.buyer_user_id,o.seller_id,o.courier_id,
  o.status order_status,o.payment_status,o.funds_status,o.currency_code,
  o.subtotal_minor,o.delivery_fee_minor,o.grand_total_minor,
  o.seller_payout_minor,o.courier_payout_minor,o.platform_revenue_minor,
  pt.id payment_transaction_id,pt.provider,pt.provider_reference,pt.settled_at,
  eh.id escrow_hold_id,eh.status escrow_status,eh.amount_minor escrow_amount_minor,
  eh.released_amount_minor
from taomoz.orders o
left join payments.payment_transactions pt on pt.id=o.payment_transaction_id
left join payments.escrow_holds eh
  on eh.reference_type='taomoz_order' and eh.reference_id=o.id::text;
grant select on taomoz.order_beneficiary_splits,taomoz.order_financial_summary to authenticated;
grant all privileges on taomoz.order_beneficiary_splits to service_role;
grant execute on function taomoz.sync_order_beneficiary_splits(uuid) to service_role;
grant execute on function taomoz.create_order_escrow(uuid,uuid,uuid) to service_role;
commit;
