-- Reconciliação única da carteira corporativa.
-- Os créditos históricos DELIGO:* pertencem ao mesmo resultado DeliGo Eats,
-- mas foram gravados antes de existir source_app em corporate_revenue_credits.
create or replace function hq.corporate_revenue_summary_v1()
returns jsonb
language sql stable security definer
set search_path = hq, public, pg_temp
as $$
  with corporate as (
    select id, available_amount
    from hq.logical_wallets
    where wallet_code = 'CORPORATE_MZN'
      and currency = 'MZN'
      and status = 'active'
    order by created_at
    limit 1
  ),
  classified as (
    select
      coalesce(sum(amount) filter (where source_app = 'deligo.orders' and status = 'credited'), 0) as deligo_current,
      coalesce(sum(amount) filter (where source_app = 'mestre24.subscriptions' and status = 'credited'), 0) as mestre24_net,
      count(*) filter (where status = 'credited') as classified_event_count
    from hq.corporate_revenue_credits
  ),
  legacy_deligo as (
    select coalesce(sum(o.amount), 0) as deligo_legacy, count(*) as deligo_legacy_event_count
    from hq.ledger_operations o
    join corporate w on w.id = o.wallet_to
    where o.operation_type = 'REVENUE'
      and o.status = 'settled'
      and o.reference_id like 'DELIGO:%'
  ),
  ledger as (
    select
      coalesce(sum(o.amount) filter (where o.wallet_to = w.id and o.operation_type = 'REVENUE' and o.status = 'settled'), 0) as revenue_inflows,
      coalesce(sum(o.amount) filter (where o.wallet_from = w.id and o.status = 'settled'), 0) as settled_outflows
    from hq.ledger_operations o
    join corporate w on o.wallet_to = w.id or o.wallet_from = w.id
  ),
  mestre24 as (
    select
      coalesce(sum(e.gross_amount) filter (where c.source_app = 'mestre24.subscriptions' and c.status = 'credited'), 0) as gross,
      coalesce(sum(e.provider_fee) filter (where c.source_app = 'mestre24.subscriptions' and c.status = 'credited'), 0) as provider_fees
    from hq.corporate_revenue_credits c
    join hq.platform_financial_events e on e.id = c.financial_event_id
  )
  select jsonb_build_object(
    'corporate_wallet_available', coalesce((select available_amount from corporate), 0),
    'deligo_eats_confirmed', (select deligo_current + deligo_legacy from classified, legacy_deligo),
    'deligo_eats_current_confirmed', (select deligo_current from classified),
    'deligo_eats_legacy_confirmed', (select deligo_legacy from legacy_deligo),
    'mestre24_confirmed', (select mestre24_net from classified),
    'mestre24_gross_confirmed', (select gross from mestre24),
    'mestre24_provider_fees', (select provider_fees from mestre24),
    'corporate_revenue_confirmed', (select deligo_current + deligo_legacy + mestre24_net from classified, legacy_deligo),
    'corporate_ledger_inflows', (select revenue_inflows from ledger),
    'corporate_ledger_outflows', (select settled_outflows from ledger),
    'corporate_ledger_net', (select revenue_inflows - settled_outflows from ledger),
    'confirmed_event_count', (select classified_event_count + deligo_legacy_event_count from classified, legacy_deligo),
    'legacy_unclassified_revenue', (select deligo_legacy from legacy_deligo)
  );
$$;

revoke all on function hq.corporate_revenue_summary_v1() from public, anon, authenticated;
grant execute on function hq.corporate_revenue_summary_v1() to service_role;
