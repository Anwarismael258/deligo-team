begin;
do $$
declare
  sarca_app_id uuid;
  reconciliation_group_id uuid;
  total_debits bigint;
  total_credits bigint;
begin
  if exists (
    select 1 from payments.financial_event_groups
    where event_code = 'sarca_migration_balance_reconciliation'
      and reference_id = 'sarca_wave2_incremental_20260730'
  ) then
    return;
  end if;

  select id into strict sarca_app_id from core.apps where slug = 'sarca';

  with wallet_net as (
    select wm.canonical_wallet_id as wallet_account_id,
      sum(case when le.entry_side = 'credit' then le.amount_minor else -le.amount_minor end) as net_minor
    from (select distinct canonical_wallet_id from staging_sarca.wallet_map) wm
    join payments.wallet_ledger_entries le
      on le.wallet_account_id = wm.canonical_wallet_id
     and le.metadata ? 'legacy_sarca_ledger_id'
    group by wm.canonical_wallet_id
  )
  select
    coalesce(sum(net_minor) filter (where net_minor > 0), 0),
    coalesce(sum(abs(net_minor)) filter (where net_minor < 0), 0)
  into total_debits, total_credits
  from wallet_net;

  if total_debits <> total_credits then
    raise exception 'Sarca reconciliation is not globally balanced: debit %, credit %',
      total_debits, total_credits;
  end if;

  if total_debits = 0 then
    return;
  end if;

  insert into payments.financial_event_groups (
    app_id, event_code, currency_code, reference_type, reference_id,
    status, expected_debits_minor, expected_credits_minor, metadata, posted_at
  ) values (
    sarca_app_id, 'sarca_migration_balance_reconciliation', 'MZN',
    'migration_batch', 'sarca_wave2_incremental_20260730', 'posted',
    total_debits, total_credits,
    jsonb_build_object(
      'reason', 'Align imported historical ledger with authoritative legacy wallet cache',
      'source_project_ref', 'oqyjzzkdcizwnkjypujs',
      'migration_batch', 'sarca_wave2_incremental'
    ), now()
  ) returning id into reconciliation_group_id;

  insert into payments.wallet_ledger_entries (
    wallet_account_id, app_id, event_group_id, entry_side, entry_type,
    currency_code, amount_minor, balance_after_minor, reference_type,
    reference_id, description, metadata
  )
  select wallet_account_id, sarca_app_id, reconciliation_group_id,
    case when net_minor > 0 then 'debit' else 'credit' end,
    'migration_reconciliation', 'MZN', abs(net_minor), 0,
    'migration_batch', 'sarca_wave2_incremental_20260730',
    'SARCA legacy wallet balance reconciliation',
    jsonb_build_object(
      'migration_batch', 'sarca_wave2_incremental',
      'pre_reconciliation_net_minor', net_minor,
      'authoritative_balance_minor', 0
    )
  from (
    select wm.canonical_wallet_id as wallet_account_id,
      sum(case when le.entry_side = 'credit' then le.amount_minor else -le.amount_minor end) as net_minor
    from (select distinct canonical_wallet_id from staging_sarca.wallet_map) wm
    join payments.wallet_ledger_entries le
      on le.wallet_account_id = wm.canonical_wallet_id
     and le.metadata ? 'legacy_sarca_ledger_id'
    group by wm.canonical_wallet_id
  ) balances
  where net_minor <> 0;
end;
$$;
commit;
