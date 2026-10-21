begin;

-- The HQ revenue ledger is the canonical source shared by the Central and
-- platform integrations.  The old summary read mestre24.financial_events,
-- which is empty in this project, so Mestre24 revenue was missing from the
-- Finance screen even after a successful subscription reconciliation.
create or replace function public.admin_canonical_finance_summary_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, payments, core, mestre24
as $function$
declare
  v_admin uuid := auth.uid();
  v_deligo_app uuid;
  v_customer_available numeric := 0;
  v_customer_pending numeric := 0;
  v_restaurant_available numeric := 0;
  v_restaurant_pending numeric := 0;
  v_courier_available numeric := 0;
  v_courier_pending numeric := 0;
  v_other_available numeric := 0;
  v_other_pending numeric := 0;
  v_deligo_profit numeric := 0;
  v_mestre24_profit numeric := 0;
  v_corporate_pending numeric := 0;
  v_corporate_reserved numeric := 0;
  v_custody_available numeric := 0;
  v_custody_pending numeric := 0;
begin
  if v_admin is null or not (
    public.is_admin()
    or exists (
      select 1
      from hq.employees e
      join hq.roles r on r.id = e.primary_role_id
      where e.auth_user_id = v_admin
        and e.status = 'active'
        and r.code in ('FINANCE', 'FINANCE_DIRECTOR')
    )
  ) then
    raise exception 'admin_only';
  end if;

  select id into v_deligo_app from core.apps where slug = 'deligo' limit 1;

  if v_deligo_app is not null then
    select
      coalesce(sum(case when wa.account_type = 'user' then wa.available_balance_minor else 0 end), 0) / 100.0,
      coalesce(sum(case when wa.account_type = 'user' then wa.pending_balance_minor else 0 end), 0) / 100.0,
      coalesce(sum(case when wa.account_type = 'merchant' then wa.available_balance_minor else 0 end), 0) / 100.0,
      coalesce(sum(case when wa.account_type = 'merchant' then wa.pending_balance_minor else 0 end), 0) / 100.0,
      coalesce(sum(case when wa.account_type = 'driver' then wa.available_balance_minor else 0 end), 0) / 100.0,
      coalesce(sum(case when wa.account_type = 'driver' then wa.pending_balance_minor else 0 end), 0) / 100.0,
      coalesce(sum(case when wa.account_type not in ('user','merchant','driver') then wa.available_balance_minor else 0 end), 0) / 100.0,
      coalesce(sum(case when wa.account_type not in ('user','merchant','driver') then wa.pending_balance_minor else 0 end), 0) / 100.0
    into v_customer_available, v_customer_pending, v_restaurant_available, v_restaurant_pending,
         v_courier_available, v_courier_pending, v_other_available, v_other_pending
    from payments.wallet_accounts wa
    where wa.app_id = v_deligo_app and wa.status in ('active', 'suspended');
  end if;

  -- Only confirmed platform fees are corporate revenue.  Partner/customer
  -- balances remain custody and are excluded from this calculation.
  select coalesce(sum(platform_fee), 0)
    into v_deligo_profit
    from hq.platform_financial_events
   where source_app = 'deligo.orders'
     and lower(coalesce(payment_status, '')) = 'confirmed';

  select coalesce(sum(platform_fee), 0)
    into v_mestre24_profit
    from hq.platform_financial_events
   where source_app = 'mestre24.subscriptions'
     and lower(coalesce(payment_status, '')) = 'confirmed';

  select coalesce(sum(amount), 0)
    into v_corporate_pending
    from public.admin_corporate_withdrawals
   where admin_id = v_admin and status in ('reserved', 'processing');

  select coalesce(sum(amount), 0)
    into v_corporate_reserved
    from public.admin_corporate_withdrawals
   where admin_id = v_admin and status in ('reserved', 'processing', 'paid');

  v_custody_available := v_customer_available + v_restaurant_available + v_courier_available + v_other_available;
  v_custody_pending := v_customer_pending + v_restaurant_pending + v_courier_pending + v_other_pending + v_corporate_reserved;

  return jsonb_build_object(
    'currency', 'MZN',
    'canonical_source', 'hq.platform_financial_events.platform_fee',
    'custody_total', round((v_custody_available + v_custody_pending)::numeric, 2),
    'custody_available', round(v_custody_available::numeric, 2),
    'custody_pending_reserved', round(v_custody_pending::numeric, 2),
    'customer_available', round(v_customer_available::numeric, 2),
    'customer_pending', round(v_customer_pending::numeric, 2),
    'restaurant_available', round(v_restaurant_available::numeric, 2),
    'restaurant_pending', round(v_restaurant_pending::numeric, 2),
    'courier_available', round(v_courier_available::numeric, 2),
    'courier_pending', round(v_courier_pending::numeric, 2),
    'corporate_profit_ledger', round((v_deligo_profit + v_mestre24_profit)::numeric, 2),
    'deligo_profit', round(v_deligo_profit::numeric, 2),
    'mestre24_profit', round(v_mestre24_profit::numeric, 2),
    'corporate_reserved_withdrawals', round(v_corporate_reserved::numeric, 2),
    'corporate_pending_withdrawals', round(v_corporate_pending::numeric, 2),
    'corporate_profit_withdrawable', round(greatest(v_deligo_profit + v_mestre24_profit - v_corporate_pending, 0)::numeric, 2),
    'withdrawal_uses_custody_total', false,
    'partner_customer_balances_excluded_from_profit', true
  );
end;
$function$;

commit;
