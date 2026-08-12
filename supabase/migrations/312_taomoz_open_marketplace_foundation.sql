begin;
alter table taomoz.seller_profiles
  add column if not exists seller_type text not null default 'individual',
  add column if not exists store_slug text,
  add column if not exists legal_name text,
  add column if not exists nuit text,
  add column if not exists province text,
  add column if not exists city text,
  add column if not exists phone text,
  add column if not exists email text,
  add column if not exists rating numeric(3,2),
  add column if not exists sales_count bigint not null default 0,
  add column if not exists followers_count bigint not null default 0;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'seller_profiles_seller_type_check'
      and conrelid = 'taomoz.seller_profiles'::regclass
  ) then
    alter table taomoz.seller_profiles
      add constraint seller_profiles_seller_type_check
      check (seller_type in ('individual', 'company'));
  end if;
end;
$$;
update taomoz.seller_profiles
set store_slug = lower(regexp_replace(trim(store_name), '[^a-zA-Z0-9]+', '-', 'g'))
  || '-' || left(id::text, 8)
where store_slug is null;
create unique index if not exists idx_taomoz_seller_store_slug
  on taomoz.seller_profiles (store_slug);
alter table taomoz.products
  add column if not exists compare_at_price_minor bigint,
  add column if not exists sku text,
  add column if not exists brand text,
  add column if not exists condition text not null default 'new',
  add column if not exists moderation_status text not null default 'approved',
  add column if not exists attributes jsonb not null default '{}'::jsonb,
  add column if not exists tags text[] not null default '{}',
  add column if not exists sold_count bigint not null default 0,
  add column if not exists review_count bigint not null default 0,
  add column if not exists is_featured boolean not null default false,
  add column if not exists published_at timestamptz;
create table if not exists taomoz.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references taomoz.products(id) on delete cascade,
  sku text,
  title text not null,
  option_values jsonb not null default '{}'::jsonb,
  price_minor bigint not null check (price_minor >= 0),
  compare_at_price_minor bigint check (
    compare_at_price_minor is null or compare_at_price_minor >= price_minor
  ),
  stock integer not null default 0 check (stock >= 0),
  image_path text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists taomoz.buyer_addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null default 'Casa',
  recipient_name text not null,
  phone text not null,
  province text not null,
  city text not null,
  district text,
  address_line text not null,
  latitude numeric(10,7),
  longitude numeric(10,7),
  delivery_notes text,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists taomoz.carts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  currency_code char(3) not null default 'MZN',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists taomoz.cart_items (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid not null references taomoz.carts(id) on delete cascade,
  product_id uuid not null references taomoz.products(id) on delete cascade,
  variant_id uuid references taomoz.product_variants(id) on delete set null,
  quantity integer not null check (quantity > 0 and quantity <= 999),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique nulls not distinct (cart_id, product_id, variant_id)
);
create table if not exists taomoz.product_reviews (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references taomoz.products(id) on delete cascade,
  order_id uuid not null references taomoz.orders(id) on delete cascade,
  buyer_user_id uuid not null references auth.users(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  title text,
  body text,
  seller_reply text,
  is_verified_purchase boolean not null default true,
  is_visible boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, order_id, buyer_user_id)
);
create table if not exists taomoz.product_favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references taomoz.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);
create index if not exists idx_taomoz_products_catalog
  on taomoz.products (is_active, moderation_status, created_at desc);
create index if not exists idx_taomoz_products_tags
  on taomoz.products using gin (tags);
create index if not exists idx_taomoz_products_attributes
  on taomoz.products using gin (attributes);
create index if not exists idx_taomoz_variants_product
  on taomoz.product_variants (product_id, is_active);
create index if not exists idx_taomoz_reviews_product
  on taomoz.product_reviews (product_id, created_at desc)
  where is_visible;
create index if not exists idx_taomoz_addresses_user
  on taomoz.buyer_addresses (user_id, is_default desc);
create index if not exists idx_taomoz_cart_items_cart
  on taomoz.cart_items (cart_id);
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'product_variants', 'buyer_addresses', 'carts', 'cart_items',
    'product_reviews', 'product_favorites'
  ]
  loop
    execute format('alter table taomoz.%I enable row level security', v_table);
  end loop;
end;
$$;
drop policy if exists taomoz_catalog_public on taomoz.products;
create policy taomoz_catalog_public on taomoz.products
for select to anon, authenticated
using (
  is_active
  and moderation_status = 'approved'
  and exists (
    select 1 from taomoz.seller_profiles s
    where s.id = products.seller_id and s.is_active and s.kyc_status = 'approved'
  )
);
drop policy if exists taomoz_sellers_public on taomoz.seller_profiles;
create policy taomoz_sellers_public on taomoz.seller_profiles
for select to anon, authenticated
using (is_active and kyc_status = 'approved');
drop policy if exists taomoz_categories_public on taomoz.categories;
create policy taomoz_categories_public on taomoz.categories
for select to anon, authenticated using (is_active);
drop policy if exists taomoz_product_images_public on taomoz.product_images;
create policy taomoz_product_images_public on taomoz.product_images
for select to anon, authenticated
using (exists (
  select 1 from taomoz.products p
  where p.id = product_images.product_id
    and p.is_active and p.moderation_status = 'approved'
));
drop policy if exists taomoz_variants_public on taomoz.product_variants;
create policy taomoz_variants_public on taomoz.product_variants
for select to anon, authenticated
using (is_active and exists (
  select 1 from taomoz.products p
  where p.id = product_variants.product_id
    and p.is_active and p.moderation_status = 'approved'
));
drop policy if exists taomoz_variants_seller_manage on taomoz.product_variants;
create policy taomoz_variants_seller_manage on taomoz.product_variants
for all to authenticated
using (exists (
  select 1 from taomoz.products p
  join taomoz.seller_profiles s on s.id = p.seller_id
  where p.id = product_variants.product_id
    and (s.user_id = auth.uid() or core.is_platform_admin(auth.uid()))
))
with check (exists (
  select 1 from taomoz.products p
  join taomoz.seller_profiles s on s.id = p.seller_id
  where p.id = product_variants.product_id
    and (s.user_id = auth.uid() or core.is_platform_admin(auth.uid()))
));
drop policy if exists taomoz_addresses_owner on taomoz.buyer_addresses;
create policy taomoz_addresses_owner on taomoz.buyer_addresses
for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());
drop policy if exists taomoz_carts_owner on taomoz.carts;
create policy taomoz_carts_owner on taomoz.carts
for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());
drop policy if exists taomoz_cart_items_owner on taomoz.cart_items;
create policy taomoz_cart_items_owner on taomoz.cart_items
for all to authenticated
using (exists (
  select 1 from taomoz.carts c
  where c.id = cart_items.cart_id and c.user_id = auth.uid()
))
with check (exists (
  select 1 from taomoz.carts c
  where c.id = cart_items.cart_id and c.user_id = auth.uid()
));
drop policy if exists taomoz_reviews_public on taomoz.product_reviews;
create policy taomoz_reviews_public on taomoz.product_reviews
for select to anon, authenticated using (is_visible);
drop policy if exists taomoz_reviews_buyer_create on taomoz.product_reviews;
create policy taomoz_reviews_buyer_create on taomoz.product_reviews
for insert to authenticated
with check (
  buyer_user_id = auth.uid()
  and exists (
    select 1 from taomoz.orders o
    join taomoz.order_items oi on oi.order_id = o.id
    where o.id = product_reviews.order_id
      and oi.product_id = product_reviews.product_id
      and o.buyer_user_id = auth.uid()
      and o.status = 'delivered'
  )
);
drop policy if exists taomoz_favorites_owner on taomoz.product_favorites;
create policy taomoz_favorites_owner on taomoz.product_favorites
for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());
grant usage on schema taomoz to anon, authenticated;
grant select on
  taomoz.categories, taomoz.seller_profiles, taomoz.products,
  taomoz.product_images, taomoz.product_variants, taomoz.product_reviews
to anon, authenticated;
grant select, insert, update, delete on
  taomoz.product_variants, taomoz.buyer_addresses, taomoz.carts,
  taomoz.cart_items, taomoz.product_reviews, taomoz.product_favorites
to authenticated;
grant all privileges on all tables in schema taomoz to service_role;
notify pgrst, 'reload schema';
commit;
