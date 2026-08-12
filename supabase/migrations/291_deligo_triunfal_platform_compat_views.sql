-- DeliGo Triunfal Platform
-- Phase 1 blueprint: compatibility views over the legacy public schema.
-- These views make the transition explicit without renaming or removing
-- any current DeliGo table.

begin;
create or replace view deligo.legacy_profiles
with (security_invoker = true)
as
select *
from public.profiles;
create or replace view deligo.legacy_restaurants
with (security_invoker = true)
as
select *
from public.restaurants;
create or replace view deligo.legacy_orders
with (security_invoker = true)
as
select *
from public.orders;
create or replace view deligo.legacy_order_items
with (security_invoker = true)
as
select *
from public.order_items;
create or replace view deligo.legacy_deliveries
with (security_invoker = true)
as
select *
from public.deliveries;
create or replace view deligo.legacy_couriers
with (security_invoker = true)
as
select *
from public.couriers;
create or replace view deligo.legacy_wallets
with (security_invoker = true)
as
select *
from public.wallets;
create or replace view deligo.legacy_wallet_ledger
with (security_invoker = true)
as
select *
from public.wallet_ledger;
create or replace view deligo.legacy_payments
with (security_invoker = true)
as
select *
from public.payments;
create or replace view deligo.legacy_refunds
with (security_invoker = true)
as
select *
from public.refunds;
create or replace view core.v_profile_alignment
with (security_invoker = true)
as
select
  cp.user_id,
  cp.primary_phone,
  cp.primary_email,
  cp.full_name as core_full_name,
  cp.display_name as core_display_name,
  cp.profile_status,
  lp.full_name as legacy_full_name,
  lp.phone as legacy_phone,
  lp.role as legacy_role,
  lp.kyc_status as legacy_kyc_status,
  lp.avatar_url as legacy_avatar_url,
  cp.created_at as core_created_at,
  lp.created_at as legacy_created_at
from core.profiles cp
left join public.profiles lp on coalesce(lp.user_id, lp.id) = cp.user_id;
create or replace view payments.v_wallet_alignment
with (security_invoker = true)
as
select
  wa.id as platform_wallet_account_id,
  wa.owner_user_id,
  wa.app_id,
  wa.account_type,
  wa.currency_code,
  wa.available_balance_minor,
  wa.pending_balance_minor,
  wa.status as platform_status,
  wa.legacy_source,
  wa.legacy_wallet_id,
  lw.id as legacy_wallet_row_id,
  lw.user_id as legacy_wallet_user_id,
  lw.balance as legacy_balance,
  lw.currency as legacy_currency,
  lw.is_active as legacy_is_active
from payments.wallet_accounts wa
left join public.wallets lw on lw.user_id = wa.owner_user_id;
comment on view deligo.legacy_profiles is 'Compatibility view over public.profiles during the platform transition.';
comment on view deligo.legacy_restaurants is 'Compatibility view over public.restaurants during the platform transition.';
comment on view deligo.legacy_orders is 'Compatibility view over public.orders during the platform transition.';
comment on view deligo.legacy_order_items is 'Compatibility view over public.order_items during the platform transition.';
comment on view deligo.legacy_deliveries is 'Compatibility view over public.deliveries during the platform transition.';
comment on view deligo.legacy_couriers is 'Compatibility view over public.couriers during the platform transition.';
comment on view deligo.legacy_wallets is 'Compatibility view over public.wallets during the platform transition.';
comment on view deligo.legacy_wallet_ledger is 'Compatibility view over public.wallet_ledger during the platform transition.';
comment on view deligo.legacy_payments is 'Compatibility view over public.payments during the platform transition.';
comment on view deligo.legacy_refunds is 'Compatibility view over public.refunds during the platform transition.';
comment on view core.v_profile_alignment is 'Review aid that compares canonical platform profiles with the current DeliGo profile rows.';
comment on view payments.v_wallet_alignment is 'Review aid that compares canonical wallet accounts with legacy DeliGo wallets.';
grant select on deligo.legacy_profiles, deligo.legacy_restaurants, deligo.legacy_orders, deligo.legacy_order_items, deligo.legacy_deliveries, deligo.legacy_couriers, deligo.legacy_wallets, deligo.legacy_wallet_ledger, deligo.legacy_payments, deligo.legacy_refunds to authenticated;
grant select on core.v_profile_alignment, payments.v_wallet_alignment to authenticated;
grant all privileges on deligo.legacy_profiles, deligo.legacy_restaurants, deligo.legacy_orders, deligo.legacy_order_items, deligo.legacy_deliveries, deligo.legacy_couriers, deligo.legacy_wallets, deligo.legacy_wallet_ledger, deligo.legacy_payments, deligo.legacy_refunds to service_role;
grant all privileges on core.v_profile_alignment, payments.v_wallet_alignment to service_role;
commit;
