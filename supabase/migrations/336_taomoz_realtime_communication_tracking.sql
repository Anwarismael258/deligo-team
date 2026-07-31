begin;
create table if not exists taomoz.conversations (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references taomoz.products(id) on delete set null,
  customer_id uuid not null references auth.users(id) on delete cascade,
  seller_id uuid not null references taomoz.seller_profiles(id) on delete cascade,
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (product_id, customer_id, seller_id)
);
create table if not exists taomoz.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references taomoz.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 4000),
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists taomoz.user_notifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references auth.users(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  link text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists taomoz.courier_presence (
  courier_id uuid primary key references taomoz.courier_profiles(id) on delete cascade,
  is_online boolean not null default false,
  latitude numeric(10,7),
  longitude numeric(10,7),
  accuracy_m numeric(10,2),
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists taomoz.shipment_location_history (
  id bigint generated always as identity primary key,
  shipment_id uuid not null references taomoz.shipments(id) on delete cascade,
  courier_id uuid not null references taomoz.courier_profiles(id) on delete cascade,
  latitude numeric(10,7) not null,
  longitude numeric(10,7) not null,
  accuracy_m numeric(10,2),
  created_at timestamptz not null default now()
);
create index if not exists idx_taomoz_messages_conversation_created
  on taomoz.messages(conversation_id, created_at);
create index if not exists idx_taomoz_notifications_profile_created
  on taomoz.user_notifications(profile_id, created_at desc);
create index if not exists idx_taomoz_shipment_locations_created
  on taomoz.shipment_location_history(shipment_id, created_at desc);
create or replace function taomoz.is_conversation_party(p_conversation_id uuid, p_user_id uuid default auth.uid())
returns boolean language sql stable security definer
set search_path=taomoz,public
as $$
  select exists(
    select 1 from taomoz.conversations c
    join taomoz.seller_profiles s on s.id=c.seller_id
    where c.id=p_conversation_id and (c.customer_id=p_user_id or s.user_id=p_user_id)
  );
$$;
create or replace function taomoz.start_product_conversation(target_product uuid)
returns uuid language plpgsql security definer
set search_path=taomoz,public
as $$
declare v_seller uuid; v_id uuid;
begin
  if auth.uid() is null then raise exception 'unauthorized'; end if;
  select seller_id into strict v_seller from taomoz.products where id=target_product and is_active;
  insert into taomoz.conversations(product_id,customer_id,seller_id)
  values(target_product,auth.uid(),v_seller)
  on conflict(product_id,customer_id,seller_id) do update set last_message_at=excluded.last_message_at
  returning id into v_id;
  return v_id;
end;
$$;
create or replace function taomoz.mark_conversation_read(target_conversation uuid)
returns void language plpgsql security definer
set search_path=taomoz,public
as $$
begin
  if not taomoz.is_conversation_party(target_conversation,auth.uid()) then raise exception 'forbidden'; end if;
  update taomoz.messages set read_at=now()
  where conversation_id=target_conversation and sender_id<>auth.uid() and read_at is null;
end;
$$;
create or replace function taomoz.mark_notification_read(target_notification uuid)
returns void language sql security definer
set search_path=taomoz,public
as $$ update taomoz.user_notifications set read_at=now() where id=target_notification and profile_id=auth.uid(); $$;
create or replace function taomoz.update_courier_presence(online boolean, lat numeric default null, lng numeric default null, accuracy numeric default null)
returns void language plpgsql security definer
set search_path=taomoz,public
as $$
declare v_courier uuid;
begin
  select id into strict v_courier from taomoz.courier_profiles where user_id=auth.uid();
  insert into taomoz.courier_presence(courier_id,is_online,latitude,longitude,accuracy_m,last_seen_at,updated_at)
  values(v_courier,online,lat,lng,accuracy,now(),now())
  on conflict(courier_id) do update set is_online=excluded.is_online,latitude=excluded.latitude,
    longitude=excluded.longitude,accuracy_m=excluded.accuracy_m,last_seen_at=now(),updated_at=now();
  if online and lat is not null and lng is not null then
    insert into taomoz.shipment_location_history(shipment_id,courier_id,latitude,longitude,accuracy_m)
    select s.id,v_courier,lat,lng,accuracy from taomoz.shipments s
    where s.courier_id=v_courier and s.status not in ('delivered','cancelled');
  end if;
end;
$$;
alter table taomoz.conversations enable row level security;
alter table taomoz.messages enable row level security;
alter table taomoz.user_notifications enable row level security;
alter table taomoz.courier_presence enable row level security;
alter table taomoz.shipment_location_history enable row level security;
create policy conversations_party on taomoz.conversations for select to authenticated
  using(taomoz.is_conversation_party(id,auth.uid()));
create policy messages_party_read on taomoz.messages for select to authenticated
  using(taomoz.is_conversation_party(conversation_id,auth.uid()));
create policy messages_party_insert on taomoz.messages for insert to authenticated
  with check(sender_id=auth.uid() and taomoz.is_conversation_party(conversation_id,auth.uid()));
create policy notifications_self on taomoz.user_notifications for select to authenticated
  using(profile_id=auth.uid());
create policy presence_self on taomoz.courier_presence for select to authenticated
  using(exists(select 1 from taomoz.courier_profiles c where c.id=courier_id and c.user_id=auth.uid()));
create policy locations_order_party on taomoz.shipment_location_history for select to authenticated
  using(exists(select 1 from taomoz.shipments s where s.id=shipment_id and taomoz.is_order_party(s.order_id,auth.uid())));
grant select on taomoz.conversations,taomoz.messages,taomoz.user_notifications,taomoz.courier_presence,taomoz.shipment_location_history to authenticated;
grant insert on taomoz.messages to authenticated;
grant all on taomoz.conversations,taomoz.messages,taomoz.user_notifications,taomoz.courier_presence,taomoz.shipment_location_history to service_role;
grant usage,select on all sequences in schema taomoz to authenticated,service_role;
grant execute on function taomoz.start_product_conversation(uuid),taomoz.mark_conversation_read(uuid),taomoz.mark_notification_read(uuid),taomoz.update_courier_presence(boolean,numeric,numeric,numeric) to authenticated,service_role;
do $$
begin
  alter publication supabase_realtime add table taomoz.conversations,taomoz.messages,taomoz.user_notifications,taomoz.courier_presence,taomoz.shipment_location_history;
exception when duplicate_object then null;
end $$;
alter table taomoz.messages replica identity full;
alter table taomoz.user_notifications replica identity full;
alter table taomoz.courier_presence replica identity full;
alter table taomoz.shipment_location_history replica identity full;
commit;
