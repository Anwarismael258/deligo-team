begin;
insert into core.roles (slug, name, scope, app_id, description)
select
  'taomoz_courier',
  'Tao Moz Courier',
  'app',
  a.id,
  'Courier account for Tao Moz marketplace deliveries.'
from core.apps a
where a.slug = 'taomoz'
on conflict (slug) do update
set app_id = excluded.app_id,
    name = excluded.name,
    description = excluded.description;
create table if not exists taomoz.buyer_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  province text,
  city text,
  default_delivery_address jsonb,
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists taomoz.seller_profiles (
  id uuid primary key,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  store_name text not null,
  description text,
  logo_url text,
  banner_url text,
  kyc_status text not null default 'pending'
    check (kyc_status in ('pending', 'under_review', 'approved', 'rejected', 'suspended')),
  is_active boolean not null default false,
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists taomoz.courier_profiles (
  id uuid primary key,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  vehicle_type text,
  plate_number text,
  kyc_status text not null default 'pending'
    check (kyc_status in ('pending', 'under_review', 'approved', 'rejected', 'suspended')),
  is_available boolean not null default false,
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists taomoz.categories (
  id uuid primary key,
  name text not null,
  slug text not null unique,
  icon text,
  is_active boolean not null default true,
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists taomoz.products (
  id uuid primary key,
  seller_id uuid not null references taomoz.seller_profiles(id) on delete cascade,
  category_id uuid references taomoz.categories(id) on delete set null,
  name text not null,
  slug text not null unique,
  description text,
  price_minor bigint not null check (price_minor >= 0),
  currency_code char(3) not null default 'MZN',
  stock integer not null default 0 check (stock >= 0),
  province text,
  is_active boolean not null default true,
  rating numeric(3,2) check (rating is null or rating between 0 and 5),
  migration_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists taomoz.product_images (
  id uuid primary key,
  product_id uuid not null references taomoz.products(id) on delete cascade,
  storage_path text not null,
  sort_order integer not null default 0,
  migration_batch text,
  created_at timestamptz not null default now()
);
create table if not exists taomoz.orders (
  id uuid primary key,
  order_number text not null unique,
  buyer_user_id uuid not null references auth.users(id) on delete restrict,
  seller_id uuid not null references taomoz.seller_profiles(id) on delete restrict,
  courier_id uuid references taomoz.courier_profiles(id) on delete set null,
  payment_transaction_id uuid references payments.payment_transactions(id) on delete set null,
  status text not null default 'pending'
    check (status in (
      'pending', 'confirmed', 'processing', 'ready_for_pickup', 'assigned',
      'picked_up', 'in_transit', 'delivered', 'cancelled', 'refunded'
    )),
  payment_status text not null default 'created'
    check (payment_status in ('created', 'pending', 'authorized', 'paid', 'failed', 'cancelled', 'refunded', 'partially_refunded')),
  funds_status text not null default 'none'
    check (funds_status in ('none', 'held_in_escrow', 'partially_released', 'released', 'partially_refunded', 'refunded')),
  currency_code char(3) not null default 'MZN',
  subtotal_minor bigint not null default 0 check (subtotal_minor >= 0),
  delivery_fee_minor bigint not null default 0 check (delivery_fee_minor >= 0),
  product_fee_rate_bps integer not null default 600 check (product_fee_rate_bps between 0 and 10000),
  delivery_fee_rate_bps integer not null default 500 check (delivery_fee_rate_bps between 0 and 10000),
  product_commission_minor bigint not null default 0 check (product_commission_minor >= 0),
  delivery_commission_minor bigint not null default 0 check (delivery_commission_minor >= 0),
  seller_payout_minor bigint not null default 0 check (seller_payout_minor >= 0),
  courier_payout_minor bigint not null default 0 check (courier_payout_minor >= 0),
  platform_revenue_minor bigint not null default 0 check (platform_revenue_minor >= 0),
  grand_total_minor bigint not null default 0 check (grand_total_minor >= 0),
  delivery_address jsonb not null default '{}'::jsonb,
  cancellation_reason text,
  migration_batch text,
  settled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists taomoz.order_items (
  id uuid primary key,
  order_id uuid not null references taomoz.orders(id) on delete cascade,
  product_id uuid references taomoz.products(id) on delete set null,
  product_name text not null,
  unit_price_minor bigint not null check (unit_price_minor >= 0),
  quantity integer not null check (quantity > 0),
  line_total_minor bigint generated always as (unit_price_minor * quantity) stored,
  migration_batch text,
  created_at timestamptz not null default now()
);
create table if not exists taomoz.shipments (
  id uuid primary key,
  tracking_number text not null unique,
  order_id uuid not null unique references taomoz.orders(id) on delete cascade,
  courier_id uuid references taomoz.courier_profiles(id) on delete set null,
  legacy_quote_id uuid,
  legacy_carrier_id uuid,
  legacy_origin_hub_id uuid,
  legacy_destination_hub_id uuid,
  status text not null default 'pending'
    check (status in (
      'pending', 'quoted', 'assigned', 'ready_for_pickup', 'picked_up',
      'in_transit', 'out_for_delivery', 'delivered', 'failed', 'cancelled', 'returned'
    )),
  pickup_address jsonb not null default '{}'::jsonb,
  delivery_address jsonb not null default '{}'::jsonb,
  recipient_name text,
  proof_of_delivery_url text,
  migration_batch text,
  picked_up_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists taomoz.shipment_events (
  id bigint generated always as identity primary key,
  shipment_id uuid not null references taomoz.shipments(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  status text,
  location jsonb,
  payload jsonb not null default '{}'::jsonb,
  legacy_event_id uuid,
  migration_batch text,
  created_at timestamptz not null default now()
);
create unique index if not exists idx_taomoz_shipment_events_legacy
  on taomoz.shipment_events (legacy_event_id)
  where legacy_event_id is not null;
create index if not exists idx_taomoz_products_seller_active on taomoz.products (seller_id, is_active);
create index if not exists idx_taomoz_products_category_active on taomoz.products (category_id, is_active);
create index if not exists idx_taomoz_product_images_product on taomoz.product_images (product_id, sort_order);
create index if not exists idx_taomoz_orders_buyer on taomoz.orders (buyer_user_id, created_at desc);
create index if not exists idx_taomoz_orders_seller on taomoz.orders (seller_id, created_at desc);
create index if not exists idx_taomoz_orders_courier on taomoz.orders (courier_id, created_at desc);
create index if not exists idx_taomoz_orders_status on taomoz.orders (status, created_at);
create index if not exists idx_taomoz_order_items_order on taomoz.order_items (order_id);
create index if not exists idx_taomoz_shipments_courier on taomoz.shipments (courier_id, status);
create index if not exists idx_taomoz_shipment_events_shipment on taomoz.shipment_events (shipment_id, created_at);
create or replace function taomoz.is_order_party(
  p_order_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = taomoz, core, public
as $$
  select exists (
    select 1
    from taomoz.orders o
    left join taomoz.seller_profiles s on s.id = o.seller_id
    left join taomoz.courier_profiles c on c.id = o.courier_id
    where o.id = p_order_id
      and (
        o.buyer_user_id = p_user_id
        or s.user_id = p_user_id
        or c.user_id = p_user_id
        or core.is_platform_admin(p_user_id)
      )
  );
$$;
create or replace function taomoz.prevent_shipment_event_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'taomoz.shipment_events is append-only; create a compensating event';
end;
$$;
drop trigger if exists trg_taomoz_shipment_events_no_update on taomoz.shipment_events;
create trigger trg_taomoz_shipment_events_no_update
before update on taomoz.shipment_events
for each row execute function taomoz.prevent_shipment_event_mutation();
drop trigger if exists trg_taomoz_shipment_events_no_delete on taomoz.shipment_events;
create trigger trg_taomoz_shipment_events_no_delete
before delete on taomoz.shipment_events
for each row execute function taomoz.prevent_shipment_event_mutation();
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'buyer_profiles', 'seller_profiles', 'courier_profiles', 'categories',
    'products', 'orders', 'shipments'
  ]
  loop
    execute format('drop trigger if exists %I on taomoz.%I', 'trg_taomoz_' || v_table || '_touch_updated_at', v_table);
    execute format(
      'create trigger %I before update on taomoz.%I for each row execute function public.touch_updated_at()',
      'trg_taomoz_' || v_table || '_touch_updated_at', v_table
    );
  end loop;
end;
$$;
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'buyer_profiles', 'seller_profiles', 'courier_profiles', 'categories',
    'products', 'product_images', 'orders', 'order_items', 'shipments', 'shipment_events'
  ]
  loop
    execute format('alter table taomoz.%I enable row level security', v_table);
  end loop;
end;
$$;
drop policy if exists taomoz_buyers_self on taomoz.buyer_profiles;
create policy taomoz_buyers_self on taomoz.buyer_profiles
for all to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()))
with check (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists taomoz_sellers_read_public on taomoz.seller_profiles;
create policy taomoz_sellers_read_public on taomoz.seller_profiles
for select to authenticated
using (is_active or user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists taomoz_sellers_manage_self on taomoz.seller_profiles;
create policy taomoz_sellers_manage_self on taomoz.seller_profiles
for all to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()))
with check (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists taomoz_couriers_read_self_or_order_party on taomoz.courier_profiles;
create policy taomoz_couriers_read_self_or_order_party on taomoz.courier_profiles
for select to authenticated
using (
  user_id = auth.uid()
  or core.is_platform_admin(auth.uid())
  or exists (
    select 1 from taomoz.orders o
    where o.courier_id = courier_profiles.id
      and taomoz.is_order_party(o.id, auth.uid())
  )
);
drop policy if exists taomoz_couriers_manage_self on taomoz.courier_profiles;
create policy taomoz_couriers_manage_self on taomoz.courier_profiles
for all to authenticated
using (user_id = auth.uid() or core.is_platform_admin(auth.uid()))
with check (user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists taomoz_categories_read on taomoz.categories;
create policy taomoz_categories_read on taomoz.categories
for select to authenticated using (is_active or core.is_platform_admin(auth.uid()));
drop policy if exists taomoz_categories_admin_write on taomoz.categories;
create policy taomoz_categories_admin_write on taomoz.categories
for all to authenticated
using (core.is_platform_admin(auth.uid()))
with check (core.is_platform_admin(auth.uid()));
drop policy if exists taomoz_products_read_catalog on taomoz.products;
create policy taomoz_products_read_catalog on taomoz.products
for select to authenticated
using (
  (is_active and exists (
    select 1 from taomoz.seller_profiles s
    where s.id = products.seller_id and s.is_active
  ))
  or exists (
    select 1 from taomoz.seller_profiles s
    where s.id = products.seller_id and s.user_id = auth.uid()
  )
  or core.is_platform_admin(auth.uid())
);
drop policy if exists taomoz_products_manage_seller on taomoz.products;
create policy taomoz_products_manage_seller on taomoz.products
for all to authenticated
using (
  exists (select 1 from taomoz.seller_profiles s where s.id = products.seller_id and s.user_id = auth.uid())
  or core.is_platform_admin(auth.uid())
)
with check (
  exists (select 1 from taomoz.seller_profiles s where s.id = products.seller_id and s.user_id = auth.uid())
  or core.is_platform_admin(auth.uid())
);
drop policy if exists taomoz_product_images_read_catalog on taomoz.product_images;
create policy taomoz_product_images_read_catalog on taomoz.product_images
for select to authenticated
using (exists (select 1 from taomoz.products p where p.id = product_images.product_id));
drop policy if exists taomoz_product_images_manage_seller on taomoz.product_images;
create policy taomoz_product_images_manage_seller on taomoz.product_images
for all to authenticated
using (
  exists (
    select 1 from taomoz.products p
    join taomoz.seller_profiles s on s.id = p.seller_id
    where p.id = product_images.product_id and s.user_id = auth.uid()
  )
  or core.is_platform_admin(auth.uid())
)
with check (
  exists (
    select 1 from taomoz.products p
    join taomoz.seller_profiles s on s.id = p.seller_id
    where p.id = product_images.product_id and s.user_id = auth.uid()
  )
  or core.is_platform_admin(auth.uid())
);
drop policy if exists taomoz_orders_read_party on taomoz.orders;
create policy taomoz_orders_read_party on taomoz.orders
for select to authenticated
using (taomoz.is_order_party(id, auth.uid()));
drop policy if exists taomoz_orders_create_buyer on taomoz.orders;
create policy taomoz_orders_create_buyer on taomoz.orders
for insert to authenticated
with check (buyer_user_id = auth.uid() or core.is_platform_admin(auth.uid()));
drop policy if exists taomoz_orders_update_party on taomoz.orders;
create policy taomoz_orders_update_party on taomoz.orders
for update to authenticated
using (taomoz.is_order_party(id, auth.uid()));
drop policy if exists taomoz_order_items_read_party on taomoz.order_items;
create policy taomoz_order_items_read_party on taomoz.order_items
for select to authenticated
using (taomoz.is_order_party(order_id, auth.uid()));
drop policy if exists taomoz_order_items_create_buyer on taomoz.order_items;
create policy taomoz_order_items_create_buyer on taomoz.order_items
for insert to authenticated
with check (
  exists (
    select 1 from taomoz.orders o
    where o.id = order_items.order_id
      and (o.buyer_user_id = auth.uid() or core.is_platform_admin(auth.uid()))
  )
);
drop policy if exists taomoz_shipments_read_party on taomoz.shipments;
create policy taomoz_shipments_read_party on taomoz.shipments
for select to authenticated
using (taomoz.is_order_party(order_id, auth.uid()));
drop policy if exists taomoz_shipments_manage_fulfilment on taomoz.shipments;
create policy taomoz_shipments_manage_fulfilment on taomoz.shipments
for all to authenticated
using (taomoz.is_order_party(order_id, auth.uid()))
with check (taomoz.is_order_party(order_id, auth.uid()));
drop policy if exists taomoz_shipment_events_read_party on taomoz.shipment_events;
create policy taomoz_shipment_events_read_party on taomoz.shipment_events
for select to authenticated
using (
  exists (
    select 1 from taomoz.shipments s
    where s.id = shipment_events.shipment_id
      and taomoz.is_order_party(s.order_id, auth.uid())
  )
);
drop policy if exists taomoz_shipment_events_insert_party on taomoz.shipment_events;
create policy taomoz_shipment_events_insert_party on taomoz.shipment_events
for insert to authenticated
with check (
  actor_user_id = auth.uid()
  and exists (
    select 1 from taomoz.shipments s
    where s.id = shipment_events.shipment_id
      and taomoz.is_order_party(s.order_id, auth.uid())
  )
);
grant select, insert, update, delete on
  taomoz.buyer_profiles, taomoz.seller_profiles, taomoz.courier_profiles,
  taomoz.categories, taomoz.products, taomoz.product_images,
  taomoz.orders, taomoz.order_items, taomoz.shipments
to authenticated;
grant select, insert on taomoz.shipment_events to authenticated;
grant all privileges on all tables in schema taomoz to service_role;
grant usage, select on all sequences in schema taomoz to authenticated, service_role;
grant execute on function taomoz.is_order_party(uuid, uuid) to authenticated, service_role;
commit;
