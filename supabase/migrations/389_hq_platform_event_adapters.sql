begin;

-- Internal append-only writers used by domain triggers. Payloads deliberately
-- contain operational identifiers and states only, never addresses, KYC files,
-- credentials or payment secrets.
create or replace function hq.capture_platform_event(
  p_platform_slug text, p_source_app text, p_source_event_id text,
  p_event_type text, p_entity_type text, p_entity_id text,
  p_user_id uuid default null, p_actor_user_id uuid default null,
  p_payload jsonb default '{}'::jsonb, p_occurred_at timestamptz default now()
) returns void language plpgsql security definer set search_path = hq, public, pg_temp as $$
declare v_platform_id uuid;
begin
  select id into v_platform_id from hq.platforms where slug = p_platform_slug and integration_status = 'connected';
  if v_platform_id is null then return; end if;
  insert into hq.platform_events(platform_id, source_app, source_event_id, event_type, entity_type, entity_id, user_id, actor_user_id, payload, occurred_at)
  values(v_platform_id, p_source_app, p_source_event_id, p_event_type, p_entity_type, p_entity_id, p_user_id, p_actor_user_id, coalesce(p_payload, '{}'::jsonb), coalesce(p_occurred_at, now()))
  on conflict(platform_id, source_app, source_event_id) where source_event_id is not null
  do update set payload = excluded.payload, occurred_at = excluded.occurred_at;
end;
$$;

create or replace function hq.capture_platform_financial_event(
  p_platform_slug text, p_source_app text, p_source_record_id text,
  p_transaction_type text, p_gross_amount numeric, p_payment_status text,
  p_entity_type text default null, p_entity_id text default null, p_user_id uuid default null,
  p_platform_fee numeric default 0, p_partner_amount numeric default 0,
  p_currency text default 'MZN', p_payment_method text default null,
  p_reference text default null, p_occurred_at timestamptz default now()
) returns void language plpgsql security definer set search_path = hq, public, pg_temp as $$
declare v_platform_id uuid;
begin
  select id into v_platform_id from hq.platforms where slug = p_platform_slug and integration_status = 'connected';
  if v_platform_id is null then return; end if;
  insert into hq.platform_financial_events(platform_id, source_app, source_record_id, transaction_type, entity_type, entity_id, user_id, gross_amount, platform_fee, partner_amount, currency, payment_method, payment_status, reference, occurred_at)
  values(v_platform_id, p_source_app, p_source_record_id, p_transaction_type, p_entity_type, p_entity_id, p_user_id, greatest(coalesce(p_gross_amount,0),0), greatest(coalesce(p_platform_fee,0),0), greatest(coalesce(p_partner_amount,0),0), coalesce(p_currency,'MZN'), p_payment_method, p_payment_status, p_reference, coalesce(p_occurred_at,now()))
  on conflict(platform_id, source_app, source_record_id) where source_record_id is not null
  do update set gross_amount=excluded.gross_amount, platform_fee=excluded.platform_fee, partner_amount=excluded.partner_amount, payment_status=excluded.payment_status, reference=excluded.reference, occurred_at=excluded.occurred_at;
end;
$$;

create or replace function hq.trg_deligo_order_event_to_hq() returns trigger
language plpgsql security definer set search_path = hq, public, pg_temp as $$
begin
  perform hq.capture_platform_event('deligo','deligo.orders','deligo:order_event:'||new.id::text,
    lower(coalesce(new.event_type,'order_updated')), 'order', new.order_id::text, null, new.actor_id,
    jsonb_strip_nulls(jsonb_build_object('old_status',new.old_status,'new_status',new.new_status)), new.created_at);
  return new;
end;
$$;

create or replace function hq.trg_sarca_trip_event_to_hq() returns trigger
language plpgsql security definer set search_path = hq, sarca, public, pg_temp as $$
declare trip_row sarca.trips;
begin
  select * into trip_row from sarca.trips where id=new.trip_id;
  perform hq.capture_platform_event('sarca','sarca.rides','sarca:trip_event:'||new.id::text,
    'ride_'||lower(new.event_type), 'ride', new.trip_id::text, trip_row.passenger_user_id, new.actor_user_id,
    jsonb_strip_nulls(jsonb_build_object('status',trip_row.status,'driver_assigned',trip_row.driver_user_id is not null)), new.created_at);
  return new;
end;
$$;

create or replace function hq.trg_sarca_trip_finance_to_hq() returns trigger
language plpgsql security definer set search_path = hq, sarca, public, pg_temp as $$
declare payment_state text;
begin
  if new.status <> 'completed' then return new; end if;
  payment_state := case when lower(coalesce(new.payment_status,'')) in ('paid','confirmed','completed') then 'confirmed' else 'pending' end;
  perform hq.capture_platform_financial_event('sarca','sarca.rides','sarca:ride:'||new.id::text||':completion',
    'ride_completion', coalesce(new.final_fare_minor,new.estimated_fare_minor,0)/100.0, payment_state,
    'ride',new.id::text,new.passenger_user_id,coalesce(new.commission_minor,0)/100.0,coalesce(new.driver_net_minor,0)/100.0,
    new.currency_code,new.payment_method,null,coalesce(new.completed_at,new.updated_at,now()));
  return new;
end;
$$;

create or replace function hq.trg_market_order_to_hq() returns trigger
language plpgsql security definer set search_path = hq, taomoz, public, pg_temp as $$
declare payment_state text;
begin
  perform hq.capture_platform_event('taomoz','deligo_market.orders','market:order:'||new.id::text||':'||new.status,
    'order_'||lower(new.status),'market_order',new.id::text,new.buyer_user_id,null,
    jsonb_build_object('payment_status',new.payment_status,'has_courier',new.courier_id is not null),new.updated_at);
  payment_state := case when lower(coalesce(new.payment_status,'')) in ('paid','confirmed') then 'confirmed'
    when lower(coalesce(new.payment_status,'')) in ('failed','cancelled') then lower(new.payment_status) else 'pending' end;
  perform hq.capture_platform_financial_event('taomoz','deligo_market.orders','market:order:'||new.id::text||':payment',
    'market_sale',coalesce(new.grand_total_minor,0)/100.0,payment_state,'market_order',new.id::text,new.buyer_user_id,
    coalesce(new.platform_revenue_minor,0)/100.0,coalesce(new.seller_payout_minor,0)+coalesce(new.courier_payout_minor,0),
    new.currency_code,null,null,new.updated_at);
  return new;
end;
$$;

create or replace function hq.trg_comunhao_church_to_hq() returns trigger
language plpgsql security definer set search_path = hq, comunhao, public, pg_temp as $$
begin
  perform hq.capture_platform_event('comunhao','comunhao.churches','comunhao:church:'||new.id::text||':'||new.status,
    case when tg_op='INSERT' then 'church_registered' else 'church_'||lower(new.status) end,
    'church',new.id::text,new.owner_user_id,new.owner_user_id,jsonb_build_object('status',new.status),new.updated_at);
  return new;
end;
$$;

create or replace function hq.trg_comunhao_membership_to_hq() returns trigger
language plpgsql security definer set search_path = hq, comunhao, public, pg_temp as $$
begin
  perform hq.capture_platform_event('comunhao','comunhao.memberships','comunhao:membership:'||new.id::text||':'||new.status,
    case when tg_op='INSERT' then 'member_joined' else 'member_'||lower(new.status) end,
    'membership',new.id::text,new.user_id,new.user_id,jsonb_build_object('church_id',new.church_id,'role',new.role),new.updated_at);
  return new;
end;
$$;

create or replace function hq.trg_comunhao_subscription_to_hq() returns trigger
language plpgsql security definer set search_path = hq, comunhao, public, pg_temp as $$
begin
  perform hq.capture_platform_event('comunhao','comunhao.subscriptions','comunhao:subscription:'||new.church_id::text||':'||new.status,
    'subscription_'||lower(new.status),'church_subscription',new.church_id::text,new.updated_by_user_id,new.updated_by_user_id,
    jsonb_build_object('plan_code',new.plan_code,'status',new.status),new.updated_at);
  return new;
end;
$$;

create or replace function hq.trg_mestre24_request_to_hq() returns trigger
language plpgsql security definer set search_path = hq, mestre24, public, pg_temp as $$
begin
  perform hq.capture_platform_event('mestre24','mestre24.requests','mestre24:request:'||new.id::text||':'||new.status,
    case when tg_op='INSERT' then 'service_requested' else 'service_'||lower(new.status) end,
    'service_request',new.id::text,new.client_user_id,new.professional_user_id,jsonb_build_object('status',new.status),new.updated_at);
  return new;
end;
$$;

create or replace function hq.trg_mestre24_subscription_to_hq() returns trigger
language plpgsql security definer set search_path = hq, mestre24, public, pg_temp as $$
declare payment_state text;
begin
  perform hq.capture_platform_event('mestre24','mestre24.subscriptions','mestre24:subscription:'||new.id::text||':'||new.status,
    'subscription_'||lower(new.status),'subscription_cycle',new.id::text,new.professional_user_id,new.professional_user_id,
    jsonb_build_object('status',new.status),new.created_at);
  payment_state := case when new.status in ('paid','active') then 'confirmed' when new.status='failed' then 'failed' when new.status='cancelled' then 'cancelled' else 'pending' end;
  perform hq.capture_platform_financial_event('mestre24','mestre24.subscriptions','mestre24:subscription:'||new.id::text,
    'professional_subscription',new.amount,payment_state,'subscription_cycle',new.id::text,new.professional_user_id,0,0,new.currency,new.provider,new.provider_reference,coalesce(new.paid_at,new.created_at));
  return new;
end;
$$;

do $$ begin
  if to_regclass('public.order_events') is not null then
    execute 'drop trigger if exists hq_deligo_order_event_to_hq on public.order_events';
    execute 'create trigger hq_deligo_order_event_to_hq after insert on public.order_events for each row execute function hq.trg_deligo_order_event_to_hq()';
  end if;
  if to_regclass('sarca.trip_events') is not null then
    execute 'drop trigger if exists hq_sarca_trip_event_to_hq on sarca.trip_events';
    execute 'create trigger hq_sarca_trip_event_to_hq after insert on sarca.trip_events for each row execute function hq.trg_sarca_trip_event_to_hq()';
  end if;
  if to_regclass('sarca.trips') is not null then
    execute 'drop trigger if exists hq_sarca_trip_finance_to_hq on sarca.trips';
    execute 'create trigger hq_sarca_trip_finance_to_hq after insert or update of status,payment_status,final_fare_minor,commission_minor,driver_net_minor on sarca.trips for each row execute function hq.trg_sarca_trip_finance_to_hq()';
  end if;
  if to_regclass('taomoz.orders') is not null then
    execute 'drop trigger if exists hq_market_order_to_hq on taomoz.orders';
    execute 'create trigger hq_market_order_to_hq after insert or update of status,payment_status,grand_total_minor,platform_revenue_minor on taomoz.orders for each row execute function hq.trg_market_order_to_hq()';
  end if;
  if to_regclass('comunhao.churches') is not null then
    execute 'drop trigger if exists hq_comunhao_church_to_hq on comunhao.churches';
    execute 'create trigger hq_comunhao_church_to_hq after insert or update of status on comunhao.churches for each row execute function hq.trg_comunhao_church_to_hq()';
  end if;
  if to_regclass('comunhao.memberships') is not null then
    execute 'drop trigger if exists hq_comunhao_membership_to_hq on comunhao.memberships';
    execute 'create trigger hq_comunhao_membership_to_hq after insert or update of status on comunhao.memberships for each row execute function hq.trg_comunhao_membership_to_hq()';
  end if;
  if to_regclass('comunhao.church_subscriptions') is not null then
    execute 'drop trigger if exists hq_comunhao_subscription_to_hq on comunhao.church_subscriptions';
    execute 'create trigger hq_comunhao_subscription_to_hq after insert or update of status on comunhao.church_subscriptions for each row execute function hq.trg_comunhao_subscription_to_hq()';
  end if;
  if to_regclass('mestre24.service_requests') is not null then
    execute 'drop trigger if exists hq_mestre24_request_to_hq on mestre24.service_requests';
    execute 'create trigger hq_mestre24_request_to_hq after insert or update of status on mestre24.service_requests for each row execute function hq.trg_mestre24_request_to_hq()';
  end if;
  if to_regclass('mestre24.subscription_cycles') is not null then
    execute 'drop trigger if exists hq_mestre24_subscription_to_hq on mestre24.subscription_cycles';
    execute 'create trigger hq_mestre24_subscription_to_hq after insert or update of status on mestre24.subscription_cycles for each row execute function hq.trg_mestre24_subscription_to_hq()';
  end if;
end $$;

revoke all on function hq.capture_platform_event(text,text,text,text,text,text,uuid,uuid,jsonb,timestamptz), hq.capture_platform_financial_event(text,text,text,text,numeric,text,text,text,uuid,numeric,numeric,text,text,text,timestamptz) from public, anon, authenticated;
notify pgrst, 'reload schema';
commit;
