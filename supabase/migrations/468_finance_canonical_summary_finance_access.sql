begin;

-- Finance has the same confirmed-read scope as the Central administrator.
-- Keep the RPC behind the authenticated user token so corporate withdrawals
-- remain scoped to auth.uid(), while resolving the real HQ role from hq.employees.
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

  select coalesce(sum(coalesce(ps.restaurant_platform_fee, 0) + coalesce(ps.courier_platform_fee, 0)), 0)
    into v_deligo_profit
    from public.payment_splits ps
   where lower(coalesce(ps.status, '')) in ('settled', 'paid', 'completed', 'confirmed');

  select coalesce(sum(platform_fee), 0)
    into v_mestre24_profit
    from mestre24.financial_events
   where lower(coalesce(status, '')) in ('paid', 'completed', 'confirmed', 'success');

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
    'canonical_source', 'payment_splits.platform_fee',
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
