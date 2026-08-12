begin;
create unique index if not exists idx_payments_ledger_sarca_legacy_id
  on payments.wallet_ledger_entries ((metadata ->> 'legacy_sarca_ledger_id'))
  where metadata ? 'legacy_sarca_ledger_id';
drop policy if exists payments_transactions_select_sarca_trip_party on payments.payment_transactions;
create policy payments_transactions_select_sarca_trip_party
on payments.payment_transactions
for select
to authenticated
using (
  app_id = (select id from core.apps where slug = 'sarca')
  and metadata ? 'sarca_trip_id'
  and exists (
    select 1
    from sarca.trips t
    where t.id = (payment_transactions.metadata ->> 'sarca_trip_id')::uuid
      and (
        t.passenger_user_id = auth.uid()
        or t.driver_user_id = auth.uid()
        or core.is_platform_admin(auth.uid())
      )
  )
);
drop policy if exists payments_wallet_ledger_select_sarca_trip_party on payments.wallet_ledger_entries;
create policy payments_wallet_ledger_select_sarca_trip_party
on payments.wallet_ledger_entries
for select
to authenticated
using (
  app_id = (select id from core.apps where slug = 'sarca')
  and (
    payments.is_wallet_owner(wallet_account_id, auth.uid())
    or (
      metadata ? 'sarca_trip_id'
      and exists (
        select 1
        from sarca.trips t
        where t.id = (wallet_ledger_entries.metadata ->> 'sarca_trip_id')::uuid
          and (
            t.passenger_user_id = auth.uid()
            or t.driver_user_id = auth.uid()
            or core.is_platform_admin(auth.uid())
          )
      )
    )
  )
);
create or replace view sarca.trip_financial_summary
with (security_invoker = true)
as
select
  t.id as trip_id,
  t.passenger_user_id,
  t.driver_user_id,
  t.status as trip_status,
  t.currency_code,
  t.final_fare_minor,
  t.commission_minor,
  t.driver_net_minor,
  pt.id as payment_transaction_id,
  pt.status as payment_status,
  pt.funds_status,
  pt.amount_minor as paid_amount_minor,
  pt.fee_minor,
  pt.provider,
  pt.provider_reference,
  pt.settled_at
from sarca.trips t
left join payments.payment_transactions pt
  on pt.id = t.payment_transaction_id;
grant select on sarca.trip_financial_summary to authenticated;
grant all privileges on sarca.trip_financial_summary to service_role;
commit;
