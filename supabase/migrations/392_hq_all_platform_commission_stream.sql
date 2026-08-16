begin;

-- The HQ financial stream is a consolidated read model. Each source event is
-- idempotent, so retries never create a second commission for the same order
-- or subscription cycle. The source domains remain their own ledgers.

create or replace function hq.trg_deligo_order_finance_to_hq() returns trigger
language plpgsql security definer set search_path = hq, public, pg_temp as $$
declare
  v_fee numeric := 0;
  v_gross numeric := greatest(coalesce(new.total_amount, new.total, 0), 0);
  v_state text;
begin
  if lower(coalesce(new.status, '')) not in ('delivered', 'completed') then
    return new;
  end if;

  select coalesce(snapshot.platform_commission_amount, 0) + coalesce(snapshot.platform_delivery_fee_amount, 0)
    into v_fee
  from public.order_financial_snapshots snapshot
  where snapshot.order_id = new.id;

  v_fee := greatest(coalesce(v_fee, nullif(new.admin_commission, 0), 0), 0);
  v_state := case
    when lower(coalesce(new.payment_status, '')) in ('failed', 'cancelled', 'refunded') then lower(new.payment_status)
    else 'confirmed'
  end;

  perform hq.capture_platform_financial_event(
    'deligo', 'deligo.orders', 'deligo:order:' || new.id::text,
    'delivery_order', v_gross, v_state, 'order', new.id::text,
    coalesce(new.client_id, new.customer_id), v_fee, greatest(v_gross - v_fee, 0),
    coalesce(nullif(new.currency, ''), 'MZN'), null, null, coalesce(new.updated_at, new.created_at, now())
  );
  return new;
end;
$$;

create or replace function hq.trg_comunhao_subscription_finance_to_hq() returns trigger
language plpgsql security definer set search_path = hq, comunhao, public, pg_temp as $$
declare
  v_price numeric := 0;
  v_currency text := 'MZN';
  v_cycle text;
  v_state text;
begin
  select coalesce(plan.price_minor, 0)::numeric / 100, coalesce(nullif(plan.currency_code, ''), 'MZN')
    into v_price, v_currency
  from comunhao.subscription_plans plan
  where plan.code = new.plan_code;

  v_cycle := coalesce(new.current_period_started_at, new.activated_at, new.created_at, now())::date::text;
  v_state := case
    when new.status = 'active' and v_price > 0 then 'confirmed'
    when new.status in ('cancelled', 'suspended') then new.status
    else 'pending'
  end;

  perform hq.capture_platform_financial_event(
    'comunhao', 'comunhao.subscriptions', 'comunhao:subscription:' || new.church_id::text || ':' || v_cycle,
    'church_subscription', v_price, v_state, 'church_subscription', new.church_id::text,
    new.updated_by_user_id, case when v_state = 'confirmed' then v_price else 0 end, 0,
    v_currency, null, null, coalesce(new.updated_at, now())
  );
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
    'professional_subscription',new.amount,payment_state,'subscription_cycle',new.id::text,new.professional_user_id,
    case when payment_state = 'confirmed' then new.amount else 0 end,0,new.currency,new.provider,new.provider_reference,coalesce(new.paid_at,new.created_at));
  return new;
end;
$$;

do $$ begin
  if to_regclass('public.orders') is not null and to_regclass('public.order_financial_snapshots') is not null then
    execute 'drop trigger if exists hq_deligo_order_finance_to_hq on public.orders';
    execute 'create trigger hq_deligo_order_finance_to_hq after insert or update of status,payment_status,total_amount,total,admin_commission on public.orders for each row execute function hq.trg_deligo_order_finance_to_hq()';
  end if;
  if to_regclass('comunhao.church_subscriptions') is not null then
    execute 'drop trigger if exists hq_comunhao_subscription_finance_to_hq on comunhao.church_subscriptions';
    execute 'create trigger hq_comunhao_subscription_finance_to_hq after insert or update of status,plan_code,current_period_started_at on comunhao.church_subscriptions for each row execute function hq.trg_comunhao_subscription_finance_to_hq()';
  end if;
  if to_regclass('mestre24.subscription_cycles') is not null then
    execute 'drop trigger if exists hq_mestre24_subscription_to_hq on mestre24.subscription_cycles';
    execute 'create trigger hq_mestre24_subscription_to_hq after insert or update of status,amount,paid_at on mestre24.subscription_cycles for each row execute function hq.trg_mestre24_subscription_to_hq()';
  end if;
end $$;

revoke all on function hq.trg_deligo_order_finance_to_hq(), hq.trg_comunhao_subscription_finance_to_hq(), hq.trg_mestre24_subscription_to_hq() from public, anon, authenticated;
notify pgrst, 'reload schema';
commit;
