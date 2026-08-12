begin;
create table if not exists taomoz.order_groups (
  id uuid primary key default gen_random_uuid(),
  checkout_number text not null unique,
  buyer_user_id uuid not null references auth.users(id) on delete restrict,
  payment_transaction_id uuid references payments.payment_transactions(id) on delete set null,
  status text not null default 'draft'
    check (status in ('draft', 'awaiting_payment', 'paid', 'processing', 'partially_completed', 'completed', 'cancelled', 'refunded')),
  payment_status text not null default 'created'
    check (payment_status in ('created', 'pending', 'authorized', 'paid', 'failed', 'cancelled', 'refunded', 'partially_refunded')),
  currency_code char(3) not null default 'MZN',
  subtotal_minor bigint not null default 0 check (subtotal_minor >= 0),
  delivery_total_minor bigint not null default 0 check (delivery_total_minor >= 0),
  grand_total_minor bigint not null default 0 check (grand_total_minor >= 0),
  delivery_address jsonb not null default '{}'::jsonb,
  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (buyer_user_id, idempotency_key)
);
alter table taomoz.orders
  add column if not exists order_group_id uuid
    references taomoz.order_groups(id) on delete restrict;
create table if not exists taomoz.checkout_sessions (
  id uuid primary key default gen_random_uuid(),
  order_group_id uuid not null unique references taomoz.order_groups(id) on delete cascade,
  buyer_user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null default 'debito',
  payment_method text not null
    check (payment_method in ('mpesa', 'emola', 'wallet', 'card', 'bank')),
  payer_phone text,
  status text not null default 'created'
    check (status in ('created', 'dispatching', 'pending_customer', 'authorized', 'paid', 'failed', 'expired', 'cancelled')),
  provider_reference text,
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  request_payload jsonb not null default '{}'::jsonb,
  provider_payload jsonb not null default '{}'::jsonb,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists taomoz.commission_rules (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid references taomoz.seller_profiles(id) on delete cascade,
  category_id uuid references taomoz.categories(id) on delete cascade,
  product_fee_rate_bps integer not null default 600
    check (product_fee_rate_bps between 0 and 10000),
  delivery_fee_rate_bps integer not null default 500
    check (delivery_fee_rate_bps between 0 and 10000),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create table if not exists taomoz.shipping_quotes (
  id uuid primary key default gen_random_uuid(),
  order_group_id uuid references taomoz.order_groups(id) on delete cascade,
  seller_id uuid not null references taomoz.seller_profiles(id) on delete cascade,
  carrier_code text not null,
  service_code text not null,
  amount_minor bigint not null check (amount_minor >= 0),
  currency_code char(3) not null default 'MZN',
  estimated_min_days integer check (estimated_min_days is null or estimated_min_days >= 0),
  estimated_max_days integer check (estimated_max_days is null or estimated_max_days >= estimated_min_days),
  pickup_address jsonb not null default '{}'::jsonb,
  delivery_address jsonb not null default '{}'::jsonb,
  status text not null default 'quoted'
    check (status in ('quoted', 'selected', 'expired', 'cancelled')),
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create table if not exists taomoz.logistics_assignments (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null unique references taomoz.shipments(id) on delete cascade,
  carrier_code text not null,
  external_shipment_reference text,
  courier_id uuid references taomoz.courier_profiles(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending', 'offered', 'accepted', 'rejected', 'assigned', 'cancelled')),
  assignment_expires_at timestamptz,
  accepted_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists taomoz.legacy_import_batches (
  id uuid primary key default gen_random_uuid(),
  source_project_ref text not null,
  source_snapshot_at timestamptz,
  batch_code text not null unique,
  status text not null default 'planned'
    check (status in ('planned', 'staging', 'validating', 'importing', 'completed', 'failed', 'rolled_back')),
  seller_count bigint not null default 0,
  product_count bigint not null default 0,
  order_count bigint not null default 0,
  unresolved_user_count bigint not null default 0,
  validation_report jsonb not null default '{}'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_taomoz_order_groups_buyer
  on taomoz.order_groups(buyer_user_id, created_at desc);
create index if not exists idx_taomoz_orders_group
  on taomoz.orders(order_group_id, seller_id);
create index if not exists idx_taomoz_checkout_provider
  on taomoz.checkout_sessions(provider, provider_reference)
  where provider_reference is not null;
create index if not exists idx_taomoz_shipping_quotes_group
  on taomoz.shipping_quotes(order_group_id, seller_id, status);
create or replace function taomoz.resolve_commission_rates(
  p_seller_id uuid,
  p_category_id uuid
)
returns table(product_fee_rate_bps integer, delivery_fee_rate_bps integer)
language sql
stable
security definer
set search_path = taomoz, public
as $$
  select r.product_fee_rate_bps, r.delivery_fee_rate_bps
  from taomoz.commission_rules r
  where r.is_active
    and r.starts_at <= now()
    and (r.ends_at is null or r.ends_at > now())
    and (r.seller_id is null or r.seller_id = p_seller_id)
    and (r.category_id is null or r.category_id = p_category_id)
  order by
    (r.seller_id is not null)::integer desc,
    (r.category_id is not null)::integer desc,
    r.starts_at desc
  limit 1;
$$;
create or replace function taomoz.create_multistore_checkout(
  p_items jsonb,
  p_delivery_address jsonb,
  p_payment_method text,
  p_payer_phone text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = taomoz, payments, core, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_group_id uuid;
  v_group_number text;
  v_seller record;
  v_item record;
  v_order_id uuid;
  v_order_number text;
  v_subtotal bigint;
  v_total_subtotal bigint := 0;
  v_delivery bigint := 0;
  v_product_rate integer := 600;
  v_delivery_rate integer := 500;
begin
  if v_user_id is null then raise exception 'authentication_required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'checkout_items_required';
  end if;
  if p_payment_method not in ('mpesa', 'emola', 'wallet', 'card', 'bank') then
    raise exception 'unsupported_payment_method';
  end if;

  select id into v_group_id from taomoz.order_groups
  where buyer_user_id = v_user_id and idempotency_key = p_idempotency_key;
  if v_group_id is not null then return v_group_id; end if;

  v_group_number := 'TM-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS')
    || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  insert into taomoz.order_groups(
    checkout_number, buyer_user_id, status, payment_status,
    delivery_address, idempotency_key
  ) values (
    v_group_number, v_user_id, 'draft', 'created',
    coalesce(p_delivery_address, '{}'::jsonb), p_idempotency_key
  ) returning id into v_group_id;

  for v_seller in
    select distinct p.seller_id
    from jsonb_to_recordset(p_items) as i(product_id uuid, variant_id uuid, quantity integer)
    join taomoz.products p on p.id = i.product_id
    join taomoz.seller_profiles s on s.id = p.seller_id
    where p.is_active and p.moderation_status = 'approved'
      and s.is_active and s.kyc_status = 'approved'
  loop
    v_order_id := gen_random_uuid();
    v_order_number := v_group_number || '-' || upper(substr(v_seller.seller_id::text, 1, 4));
    v_subtotal := 0;

    select coalesce(sum(
      coalesce(v.price_minor, p.price_minor) * i.quantity
    ), 0)::bigint
    into v_subtotal
    from jsonb_to_recordset(p_items) as i(product_id uuid, variant_id uuid, quantity integer)
    join taomoz.products p on p.id = i.product_id
    left join taomoz.product_variants v
      on v.id = i.variant_id and v.product_id = p.id and v.is_active
    where p.seller_id = v_seller.seller_id
      and i.quantity > 0
      and i.quantity <= coalesce(v.stock, p.stock);

    if v_subtotal <= 0 then raise exception 'invalid_or_unavailable_items'; end if;

    select coalesce(r.product_fee_rate_bps, 600),
           coalesce(r.delivery_fee_rate_bps, 500)
      into v_product_rate, v_delivery_rate
    from taomoz.resolve_commission_rates(v_seller.seller_id, null) r;

    insert into taomoz.orders(
      id, order_number, order_group_id, buyer_user_id, seller_id,
      status, payment_status, funds_status, subtotal_minor,
      delivery_fee_minor, product_fee_rate_bps, delivery_fee_rate_bps,
      grand_total_minor, delivery_address
    ) values (
      v_order_id, v_order_number, v_group_id, v_user_id, v_seller.seller_id,
      'pending', 'created', 'none', v_subtotal,
      0, v_product_rate, v_delivery_rate,
      v_subtotal, coalesce(p_delivery_address, '{}'::jsonb)
    );

    for v_item in
      select i.product_id, i.variant_id, i.quantity, p.name,
             coalesce(v.price_minor, p.price_minor) as unit_price_minor
      from jsonb_to_recordset(p_items) as i(product_id uuid, variant_id uuid, quantity integer)
      join taomoz.products p on p.id = i.product_id
      left join taomoz.product_variants v
        on v.id = i.variant_id and v.product_id = p.id and v.is_active
      where p.seller_id = v_seller.seller_id
        and i.quantity > 0
        and i.quantity <= coalesce(v.stock, p.stock)
    loop
      insert into taomoz.order_items(
        id, order_id, product_id, product_name, unit_price_minor, quantity
      ) values (
        gen_random_uuid(), v_order_id, v_item.product_id, v_item.name,
        v_item.unit_price_minor, v_item.quantity
      );
    end loop;
    v_total_subtotal := v_total_subtotal + v_subtotal;
  end loop;

  if not exists (select 1 from taomoz.orders where order_group_id = v_group_id) then
    raise exception 'no_eligible_products';
  end if;

  update taomoz.order_groups set
    subtotal_minor = v_total_subtotal,
    delivery_total_minor = v_delivery,
    grand_total_minor = v_total_subtotal + v_delivery,
    status = 'awaiting_payment',
    payment_status = 'pending',
    updated_at = now()
  where id = v_group_id;

  insert into taomoz.checkout_sessions(
    order_group_id, buyer_user_id, provider, payment_method,
    payer_phone, status, request_payload
  ) values (
    v_group_id, v_user_id,
    case when p_payment_method in ('mpesa','emola') then 'debito' else p_payment_method end,
    p_payment_method, p_payer_phone, 'created',
    jsonb_build_object('amount_minor', v_total_subtotal + v_delivery,
                       'currency_code', 'MZN')
  );
  return v_group_id;
end;
$$;
create or replace function taomoz.mark_checkout_paid(
  p_order_group_id uuid,
  p_payment_transaction_id uuid
)
returns void
language plpgsql
security definer
set search_path = taomoz, payments, core, public
as $$
declare
  v_group taomoz.order_groups%rowtype;
  v_payment payments.payment_transactions%rowtype;
  v_order record;
  v_source_wallet uuid;
begin
  if current_user not in ('postgres', 'service_role') then
    raise exception 'trusted_backend_required';
  end if;
  select * into strict v_group from taomoz.order_groups
    where id = p_order_group_id for update;
  select * into strict v_payment from payments.payment_transactions
    where id = p_payment_transaction_id for update;
  if v_payment.amount_minor <> v_group.grand_total_minor then
    raise exception 'payment_amount_mismatch';
  end if;

  select id into v_source_wallet from payments.wallet_accounts
  where account_code = 'taomoz:provider:debito:MZN';
  if v_source_wallet is null then
    insert into payments.wallet_accounts(
      app_id, account_code, account_type, currency_code, metadata
    ) select id, 'taomoz:provider:debito:MZN', 'system', 'MZN',
             '{"provider":"debito","purpose":"clearing"}'::jsonb
      from core.apps where slug = 'taomoz'
      returning id into v_source_wallet;
  end if;

  update payments.payment_transactions set
    status = 'settled', funds_status = 'held_in_escrow', settled_at = now()
  where id = p_payment_transaction_id;

  for v_order in select id from taomoz.orders where order_group_id = p_order_group_id
  loop
    update taomoz.orders set
      payment_transaction_id = p_payment_transaction_id,
      payment_status = 'paid', funds_status = 'held_in_escrow',
      status = 'confirmed', updated_at = now()
    where id = v_order.id;
    perform taomoz.create_order_escrow(
      v_order.id, p_payment_transaction_id, v_source_wallet
    );
  end loop;

  update taomoz.order_groups set
    payment_transaction_id = p_payment_transaction_id,
    payment_status = 'paid', status = 'paid', updated_at = now()
  where id = p_order_group_id;
  update taomoz.checkout_sessions set
    status = 'paid', updated_at = now()
  where order_group_id = p_order_group_id;
end;
$$;
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'order_groups', 'checkout_sessions', 'commission_rules',
    'shipping_quotes', 'logistics_assignments', 'legacy_import_batches'
  ]
  loop execute format('alter table taomoz.%I enable row level security', v_table);
  end loop;
end;
$$;
drop policy if exists taomoz_order_groups_buyer on taomoz.order_groups;
create policy taomoz_order_groups_buyer on taomoz.order_groups
for select to authenticated
using (buyer_user_id = auth.uid() or core.has_permission(auth.uid(), 'taomoz.operations.read'));
drop policy if exists taomoz_checkout_sessions_buyer on taomoz.checkout_sessions;
create policy taomoz_checkout_sessions_buyer on taomoz.checkout_sessions
for select to authenticated
using (buyer_user_id = auth.uid() or core.has_permission(auth.uid(), 'taomoz.operations.read'));
drop policy if exists taomoz_shipping_quotes_buyer on taomoz.shipping_quotes;
create policy taomoz_shipping_quotes_buyer on taomoz.shipping_quotes
for select to authenticated
using (exists (
  select 1 from taomoz.order_groups g
  where g.id = shipping_quotes.order_group_id
    and (g.buyer_user_id = auth.uid()
      or core.has_permission(auth.uid(), 'taomoz.operations.read'))
));
grant select on taomoz.order_groups, taomoz.checkout_sessions,
  taomoz.shipping_quotes, taomoz.logistics_assignments to authenticated;
grant execute on function taomoz.create_multistore_checkout(jsonb, jsonb, text, text, text)
  to authenticated, service_role;
revoke all on function taomoz.mark_checkout_paid(uuid, uuid) from public, anon, authenticated;
grant execute on function taomoz.mark_checkout_paid(uuid, uuid) to service_role;
grant all privileges on all tables in schema taomoz to service_role;
notify pgrst, 'reload schema';
commit;
