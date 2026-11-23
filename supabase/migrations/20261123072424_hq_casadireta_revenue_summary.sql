begin;

-- Include CasaDireta's confirmed net subscriptions in the same Central
-- revenue and withdrawal availability views used by Finance.
create or replace function hq.corporate_revenue_availability_v1()
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  revenue numeric := 0;
  sent numeric := 0;
  committed numeric := 0;
  cash numeric := 0;
  wid uuid;
begin
  select id, available_amount into wid, cash
  from hq.logical_wallets
  where wallet_code = 'CORPORATE_MZN' and currency = 'MZN' and status = 'active'
  order by created_at limit 1;
  if wid is null then raise exception 'corporate_wallet_not_found'; end if;

  select coalesce(sum(e.platform_fee), 0) into revenue
  from hq.platform_financial_events e
  join hq.platforms p on p.id = e.platform_id
  where p.slug in ('deligo', 'mestre24', 'sarca', 'comunhao', 'taomoz', 'casadireta')
    and e.currency = 'MZN' and e.payment_status = 'confirmed'
    and e.metadata->>'test_mode' is distinct from 'true'
    and e.metadata->>'fictitious' is distinct from 'true'
    and coalesce(e.source_record_id, '') not like 'TEST-%';

  select coalesce(sum(amount), 0) into sent
  from hq.ledger_operations
  where wallet_from = wid and status = 'settled'
    and operation_type in ('INTERNAL_TRANSFER', 'WITHDRAWAL', 'PAYOUT');

  select coalesce(sum(w.amount), 0) into committed
  from public.admin_corporate_withdrawals w
  where (w.status in ('approved', 'reserved', 'processing', 'paid')
    or (w.status = 'pending_approval' and exists (
      select 1 from public.admin_corporate_withdrawal_approvals a
      where a.withdrawal_id = w.id and a.status = 'pending' and a.otp_expires_at > now()
    )))
    and not exists (
      select 1 from hq.ledger_operations o
      where o.wallet_from = wid and o.reference_id = w.id::text and o.status = 'settled'
    );

  return jsonb_build_object(
    'corporate_revenue_confirmed', round(revenue, 2),
    'corporate_revenue_transferred', round(sent, 2),
    'corporate_pending_withdrawals', round(committed, 2),
    'corporate_wallet_available', round(cash, 2),
    'corporate_profit_withdrawable', round(greatest(least(cash, revenue - sent) - committed, 0), 2),
    'source', 'hq.platform_financial_events + corporate settled transfers and live approvals'
  );
end;
$function$;

create or replace function hq.corporate_revenue_summary_v1()
returns jsonb
language sql
stable
security definer
set search_path = hq, public, pg_temp
as $function$
with corporate as (
  select id, available_amount from hq.logical_wallets
  where wallet_code = 'CORPORATE_MZN' and currency = 'MZN' and status = 'active'
  order by created_at limit 1
), classified as (
  select
    coalesce(sum(amount) filter (where source_app = 'deligo.orders' and status = 'credited'), 0) as deligo_current,
    coalesce(sum(amount) filter (where source_app = 'mestre24.subscriptions' and status = 'credited'), 0) as mestre24_net,
    coalesce(sum(amount) filter (where source_app = 'casadireta.subscriptions' and status = 'credited'), 0) as casadireta_net,
    count(*) filter (where status = 'credited') as classified_event_count
  from hq.corporate_revenue_credits
), legacy_deligo as (
  select coalesce(sum(o.amount), 0) as deligo_legacy, count(*) as deligo_legacy_event_count
  from hq.ledger_operations o join corporate w on w.id = o.wallet_to
  where o.operation_type = 'REVENUE' and o.status = 'settled' and o.reference_id like 'DELIGO:%'
), ledger as (
  select
    coalesce(sum(o.amount) filter (where o.wallet_to = w.id and o.operation_type = 'REVENUE' and o.status = 'settled'), 0) as revenue_inflows,
    coalesce(sum(o.amount) filter (where o.wallet_from = w.id and o.status = 'settled'), 0) as settled_outflows
  from hq.ledger_operations o join corporate w on o.wallet_to = w.id or o.wallet_from = w.id
), mestre24 as (
  select
    coalesce(sum(e.gross_amount) filter (where c.source_app = 'mestre24.subscriptions' and c.status = 'credited'), 0) as gross,
    coalesce(sum(e.provider_fee) filter (where c.source_app = 'mestre24.subscriptions' and c.status = 'credited'), 0) as provider_fees
  from hq.corporate_revenue_credits c join hq.platform_financial_events e on e.id = c.financial_event_id
), casadireta as (
  select
    coalesce(sum(e.gross_amount) filter (where c.source_app = 'casadireta.subscriptions' and c.status = 'credited'), 0) as gross,
    coalesce(sum(e.provider_fee) filter (where c.source_app = 'casadireta.subscriptions' and c.status = 'credited'), 0) as provider_fees
  from hq.corporate_revenue_credits c join hq.platform_financial_events e on e.id = c.financial_event_id
)
select jsonb_build_object(
  'corporate_wallet_available', coalesce((select available_amount from corporate), 0),
  'deligo_eats_confirmed', (select deligo_current + deligo_legacy from classified, legacy_deligo),
  'deligo_eats_current_confirmed', (select deligo_current from classified),
  'deligo_eats_legacy_confirmed', (select deligo_legacy from legacy_deligo),
  'mestre24_confirmed', (select mestre24_net from classified),
  'mestre24_gross_confirmed', (select gross from mestre24),
  'mestre24_provider_fees', (select provider_fees from mestre24),
  'casadireta_confirmed', (select casadireta_net from classified),
  'casadireta_gross_confirmed', (select gross from casadireta),
  'casadireta_provider_fees', (select provider_fees from casadireta),
  'corporate_revenue_confirmed', (select deligo_current + deligo_legacy + mestre24_net + casadireta_net from classified, legacy_deligo),
  'corporate_ledger_inflows', (select revenue_inflows from ledger),
  'corporate_ledger_outflows', (select settled_outflows from ledger),
  'corporate_ledger_net', (select revenue_inflows - settled_outflows from ledger),
  'confirmed_event_count', (select classified_event_count + deligo_legacy_event_count from classified, legacy_deligo),
  'legacy_unclassified_revenue', (select deligo_legacy from legacy_deligo)
);
$function$;

commit;
