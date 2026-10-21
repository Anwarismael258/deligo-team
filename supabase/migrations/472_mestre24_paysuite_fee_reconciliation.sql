begin;

-- PaySuite reports the subscription amount and its fee as separate
-- transactions. Corporate revenue is the net amount after that provider fee;
-- the gross and fee remain on the financial event for audit/reconciliation.
create or replace function hq.paysuite_provider_fee_v1(p_metadata jsonb, p_gross_amount numeric)
returns numeric
language plpgsql
immutable
set search_path = hq, public, pg_temp
as $function$
declare
  v_raw text;
  v_fee numeric;
begin
  v_raw := coalesce(
    p_metadata #>> '{data,provider_fee}',
    p_metadata #>> '{data,providerFee}',
    p_metadata #>> '{data,fee}',
    p_metadata #>> '{data,taxa}',
    p_metadata #>> '{data,transaction_fee}',
    p_metadata #>> '{provider_fee}',
    p_metadata #>> '{providerFee}',
    p_metadata #>> '{fee}',
    p_metadata #>> '{taxa}',
    p_metadata #>> '{transaction_fee}'
  );
  if v_raw is not null and v_raw ~ '^[0-9]+(\.[0-9]+)?$' then
    v_fee := v_raw::numeric;
  end if;
  -- Current PaySuite subscription pricing charges 3% when the callback does
  -- not include the separate fee transaction in its payload.
  return round(least(greatest(coalesce(v_fee, p_gross_amount * 0.03), 0), p_gross_amount), 2);
end;
$function$;

create or replace function hq.normalize_mestre24_financial_event()
returns trigger
language plpgsql
security definer
set search_path = hq, public, pg_temp
as $function$
declare
  v_provider_fee numeric;
begin
  if new.source_app = 'mestre24.subscriptions'
     and lower(coalesce(new.payment_status, '')) = 'confirmed'
     and coalesce(new.gross_amount, 0) > 0 then
    v_provider_fee := round(greatest(coalesce(new.provider_fee, 0), hq.paysuite_provider_fee_v1(coalesce(new.metadata, '{}'::jsonb), new.gross_amount)), 2);
    v_provider_fee := least(v_provider_fee, new.gross_amount);
    new.provider_fee := v_provider_fee;
    new.platform_fee := greatest(round(new.gross_amount - v_provider_fee - coalesce(new.partner_amount, 0), 2), 0);
    new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_build_object(
      'gross_amount', new.gross_amount,
      'provider_fee', v_provider_fee,
      'net_corporate_amount', new.platform_fee,
      'accounting_basis', 'gross_less_paysuite_fee'
    );
  end if;
  return new;
end;
$function$;

drop trigger if exists hq_normalize_mestre24_financial_event on hq.platform_financial_events;
create trigger hq_normalize_mestre24_financial_event
before insert or update of gross_amount, platform_fee, provider_fee, partner_amount, payment_status, metadata
on hq.platform_financial_events
for each row execute function hq.normalize_mestre24_financial_event();

-- Correct events created before this migration. The second block below also
-- adjusts the already-created revenue credit and ledger operation exactly
-- once, so the CORPORATE_MZN balance moves from gross to net without creating
-- a duplicate revenue entry.
update hq.platform_financial_events
set provider_fee = hq.paysuite_provider_fee_v1(coalesce(metadata, '{}'::jsonb), gross_amount)
where source_app = 'mestre24.subscriptions'
  and lower(coalesce(payment_status, '')) = 'confirmed'
  and coalesce(provider_fee, 0) = 0
  and coalesce(gross_amount, 0) > 0;

do $function$
declare
  v_credit record;
  v_wallet_id uuid;
  v_delta numeric;
begin
  select id into v_wallet_id
  from hq.logical_wallets
  where wallet_code = 'CORPORATE_MZN' and currency = 'MZN' and status = 'active'
  order by created_at limit 1;

  if v_wallet_id is null then
    raise exception 'corporate_wallet_not_found';
  end if;

  for v_credit in
    select c.id as credit_id, c.amount as credited_amount,
           e.platform_fee as expected_amount, c.credit_operation_id
    from hq.corporate_revenue_credits c
    join hq.platform_financial_events e on e.id = c.financial_event_id
    where c.status = 'credited'
      and c.source_app = 'mestre24.subscriptions'
      and e.source_app = 'mestre24.subscriptions'
      and e.payment_status = 'confirmed'
  loop
    v_delta := round(v_credit.expected_amount - v_credit.credited_amount, 2);
    if v_delta <> 0 then
      update hq.logical_wallets
      set available_amount = available_amount + v_delta, updated_at = now()
      where id = v_wallet_id;

      update hq.ledger_operations
      set amount = v_credit.expected_amount,
          metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
            'reconciled_provider_fee', true,
            'reconciliation_reason', 'PaySuite 3 percent subscription fee'
          )
      where id = v_credit.credit_operation_id;

      update hq.corporate_revenue_credits
      set amount = v_credit.expected_amount, updated_at = now()
      where id = v_credit.credit_id;
    end if;
  end loop;
end;
$function$;

create or replace function hq.corporate_revenue_summary_v1()
returns jsonb
language sql stable security definer
set search_path = hq, public, pg_temp
as $$
  select jsonb_build_object(
    'corporate_wallet_available', coalesce((select available_amount from hq.logical_wallets where wallet_code = 'CORPORATE_MZN' and currency = 'MZN' and status = 'active' order by created_at limit 1), 0),
    'deligo_eats_confirmed', coalesce((select sum(amount) from hq.corporate_revenue_credits where source_app = 'deligo.orders' and status = 'credited'), 0),
    'mestre24_confirmed', coalesce((select sum(amount) from hq.corporate_revenue_credits where source_app = 'mestre24.subscriptions' and status = 'credited'), 0),
    'mestre24_gross_confirmed', coalesce((select sum(e.gross_amount) from hq.corporate_revenue_credits c join hq.platform_financial_events e on e.id = c.financial_event_id where c.source_app = 'mestre24.subscriptions' and c.status = 'credited'), 0),
    'mestre24_provider_fees', coalesce((select sum(e.provider_fee) from hq.corporate_revenue_credits c join hq.platform_financial_events e on e.id = c.financial_event_id where c.source_app = 'mestre24.subscriptions' and c.status = 'credited'), 0),
    'confirmed_event_count', (select count(*) from hq.corporate_revenue_credits where status = 'credited')
  );
$$;

commit;
