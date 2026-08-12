begin;
create unique index if not exists idx_payments_wallets_taomoz_legacy
  on payments.wallet_accounts (legacy_source, legacy_wallet_id)
  where legacy_source='taomoz' and legacy_wallet_id is not null;
create unique index if not exists idx_payments_groups_taomoz_legacy_tx
  on payments.financial_event_groups ((metadata->>'legacy_taomoz_transaction_id'))
  where metadata ? 'legacy_taomoz_transaction_id';
create unique index if not exists idx_payments_ledger_taomoz_legacy_tx
  on payments.wallet_ledger_entries ((metadata->>'legacy_taomoz_transaction_id'))
  where metadata ? 'legacy_taomoz_transaction_id';
create unique index if not exists idx_payments_escrow_taomoz_legacy_id
  on payments.escrow_holds ((metadata->>'legacy_taomoz_escrow_id'))
  where metadata ? 'legacy_taomoz_escrow_id';
create unique index if not exists idx_taomoz_splits_legacy_id
  on taomoz.order_beneficiary_splits ((metadata->>'legacy_taomoz_split_id'))
  where metadata ? 'legacy_taomoz_split_id';
commit;
