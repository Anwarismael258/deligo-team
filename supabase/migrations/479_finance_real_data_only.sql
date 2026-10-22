begin;

-- Finance must never present provisioned personas, fictitious balances or
-- internal retirement wallets as real money. Historical ledger rows remain
-- intact; this only changes the read model used by the Central dashboard.
create or replace function hq.financial_platform_summary_v1()
returns jsonb
language sql
stable
security definer
set search_path = hq, public, payments, core, pg_temp
as $$
  with real_events as (
    select e.*
    from hq.platform_financial_events e
    where e.currency = 'MZN'
      and e.payment_status = 'confirmed'
      and coalesce(e.metadata->>'test_mode', 'false') <> 'true'
      and coalesce(e.metadata->>'fictitious', 'false') <> 'true'
      and coalesce(e.source_record_id, '') not like 'TEST-%'
  ),
  real_wallets as (
    select wa.*
    from payments.wallet_accounts wa
    where wa.currency_code = 'MZN'
      and wa.status in ('active', 'suspended')
      and wa.account_type not in ('platform', 'system', 'escrow')
      and coalesce(wa.metadata->>'test_mode', 'false') <> 'true'
      and coalesce(wa.metadata->>'fictitious', 'false') <> 'true'
      and coalesce(wa.metadata->>'is_test_user', 'false') <> 'true'
      and coalesce(wa.metadata->>'internal_only', 'false') <> 'true'
      and coalesce(wa.metadata->>'provisioning_source', '') not like 'ecosystem_test%'
      and coalesce(wa.account_code, '') not like 'TEST-%'
  ),
  platform_rows as (
    select
      p.slug,
      p.name,
      a.id as app_id,
      coalesce((select sum(e.gross_amount) from real_events e where e.platform_id = p.id), 0) as gross_confirmed,
      coalesce((select sum(e.platform_fee) from real_events e where e.platform_id = p.id), 0) as central_revenue_confirmed,
      coalesce((select sum(e.provider_fee) from real_events e where e.platform_id = p.id), 0) as provider_fees_confirmed,
      coalesce((select sum(w.available_balance_minor) / 100.0 from real_wallets w where w.app_id = a.id), 0) as wallet_available,
      coalesce((select sum(w.pending_balance_minor) / 100.0 from real_wallets w where w.app_id = a.id), 0) as wallet_pending
    from hq.platforms p
    left join core.apps a on a.slug = p.slug
    where p.slug in ('deligo', 'mestre24', 'sarca', 'comunhao', 'taomoz')
  ),
  global_wallets as (
    select coalesce(sum(available_balance_minor), 0) / 100.0 as available,
           coalesce(sum(pending_balance_minor), 0) / 100.0 as pending
    from real_wallets
    where app_id is null and owner_user_id is not null
  ),
  corporate as (
    select coalesce(sum(available_amount), 0) as available
    from hq.logical_wallets
    where wallet_code = 'CORPORATE_MZN' and currency = 'MZN' and status = 'active'
  ),
  unclassified as (
    select coalesce(sum(o.amount), 0) as amount
    from hq.ledger_operations o
    join hq.logical_wallets w on w.id = o.wallet_to
    where w.wallet_code = 'CORPORATE_MZN'
      and o.operation_type = 'REVENUE'
      and o.status = 'settled'
      and o.reference_id like 'DELIGO:%'
      and not exists (select 1 from hq.corporate_revenue_credits c where c.credit_operation_id = o.id)
  ),
  totals as (
    select coalesce(sum(gross_confirmed), 0) as gross,
           coalesce(sum(central_revenue_confirmed), 0) as revenue,
           coalesce(sum(wallet_available), 0) as app_wallet_available,
           coalesce(sum(wallet_pending), 0) as app_wallet_pending
    from platform_rows
  )
  select jsonb_build_object(
    'currency', 'MZN',
    'source', 'real hq.platform_financial_events + real payments.wallet_accounts + hq.logical_wallets',
    'platforms', coalesce((select jsonb_agg(jsonb_build_object(
      'slug', slug, 'name', name,
      'gross_confirmed', round(gross_confirmed::numeric, 2),
      'central_revenue_confirmed', round(central_revenue_confirmed::numeric, 2),
      'provider_fees_confirmed', round(provider_fees_confirmed::numeric, 2),
      'wallet_available', round(wallet_available::numeric, 2),
      'wallet_pending', round(wallet_pending::numeric, 2),
      'funds_total', round((wallet_available + wallet_pending)::numeric, 2)
    ) order by name) from platform_rows), '[]'::jsonb),
    'global_user_wallet_available', round((select available from global_wallets)::numeric, 2),
    'global_user_wallet_pending', round((select pending from global_wallets)::numeric, 2),
    'corporate_wallet_available', round((select available from corporate)::numeric, 2),
    'central_revenue_confirmed', round((select revenue from totals)::numeric, 2),
    'gross_platform_volume_confirmed', round((select gross from totals)::numeric, 2),
    'platform_wallet_available', round((select app_wallet_available from totals)::numeric, 2),
    'platform_wallet_pending', round((select app_wallet_pending from totals)::numeric, 2),
    'user_wallets_available', round(((select app_wallet_available from totals) + (select available from global_wallets))::numeric, 2),
    'user_wallets_pending', round(((select app_wallet_pending from totals) + (select pending from global_wallets))::numeric, 2),
    'total_funds_controlled_available', round(((select available from corporate) + (select app_wallet_available from totals) + (select available from global_wallets))::numeric, 2),
    'total_funds_controlled_pending', round(((select app_wallet_pending from totals) + (select pending from global_wallets))::numeric, 2),
    'unclassified_legacy_corporate_amount', round((select amount from unclassified)::numeric, 2),
    'legacy_revenue_included', false,
    'test_data_included', false
  from c, global_wallets g, totals t;
$$;

revoke all on function hq.financial_platform_summary_v1() from public, anon, authenticated;
grant execute on function hq.financial_platform_summary_v1() to service_role;

create or replace function hq.corporate_revenue_summary_v1()
returns jsonb
language sql
stable
security definer
set search_path = hq, public, pg_temp
as $$
  with real_credits as (
    select c.*, e.gross_amount, e.provider_fee, e.metadata, e.source_record_id
    from hq.corporate_revenue_credits c
    join hq.platform_financial_events e on e.id = c.financial_event_id
    where c.status = 'credited'
      and coalesce(e.metadata->>'test_mode', 'false') <> 'true'
      and coalesce(e.metadata->>'fictitious', 'false') <> 'true'
      and coalesce(e.source_record_id, '') not like 'TEST-%'
  )
  select jsonb_build_object(
    'corporate_wallet_available', coalesce((select available_amount from hq.logical_wallets where wallet_code = 'CORPORATE_MZN' and currency = 'MZN' and status = 'active' order by created_at limit 1), 0),
    'deligo_eats_confirmed', coalesce((select sum(amount) from real_credits where source_app = 'deligo.orders'), 0),
    'mestre24_confirmed', coalesce((select sum(amount) from real_credits where source_app = 'mestre24.subscriptions'), 0),
    'mestre24_gross_confirmed', coalesce((select sum(gross_amount) from real_credits where source_app = 'mestre24.subscriptions'), 0),
    'mestre24_provider_fees', coalesce((select sum(provider_fee) from real_credits where source_app = 'mestre24.subscriptions'), 0),
    'corporate_revenue_confirmed', coalesce((select sum(amount) from real_credits), 0),
    'legacy_unclassified_revenue', coalesce((select sum(o.amount) from hq.ledger_operations o join hq.logical_wallets w on w.id = o.wallet_to where w.wallet_code = 'CORPORATE_MZN' and o.operation_type = 'REVENUE' and o.status = 'settled' and o.reference_id like 'DELIGO:%' and not exists (select 1 from hq.corporate_revenue_credits c where c.credit_operation_id = o.id)), 0),
    'legacy_revenue_included', false,
    'test_data_included', false,
    'confirmed_event_count', (select count(*) from real_credits)
  );
$$;

revoke all on function hq.corporate_revenue_summary_v1() from public, anon, authenticated;
grant execute on function hq.corporate_revenue_summary_v1() to service_role;

commit;
