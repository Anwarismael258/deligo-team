-- Launch reset: remove all fictitious/test wallet balances before real-money go-live.
-- Ledger history is retained; every non-zero balance is closed with an audited
-- debit entry so reconciliation remains possible.

begin;

do $reset$
declare
  v_wallet record;
  v_balance bigint;
begin
  for v_wallet in
    select w.id, w.app_id, w.available_balance_minor, w.pending_balance_minor,
           w.account_code
    from payments.wallet_accounts w
    where coalesce((w.metadata->>'test_mode')::boolean, false)
       or coalesce((w.metadata->>'fictitious')::boolean, false)
       or w.metadata->>'provisioning_source' in (
         'ecosystem_test_personas_395',
         'ecosystem_persona_consolidation_421'
       )
       or w.account_code = 'CENTRAL-INTERNAL-RETIRED-ECOSYSTEM'
    for update
  loop
    v_balance := coalesce(v_wallet.available_balance_minor, 0)
      + coalesce(v_wallet.pending_balance_minor, 0);

    if v_balance > 0 then
      insert into payments.wallet_ledger_entries (
        wallet_account_id, app_id, entry_side, entry_type, currency_code,
        amount_minor, balance_after_minor, reference_type, reference_id,
        description, metadata
      ) values (
        v_wallet.id, v_wallet.app_id, 'debit', 'launch_test_balance_reset',
        'MZN', v_balance, 0, 'launch_reset',
        '422-zero-test-balances',
        'Reposição de saldo fictício para lançamento com dinheiro real',
        jsonb_build_object('test_mode', true, 'fictitious', true,
          'migration', '422_zero_all_test_balances_for_launch',
          'previous_balance_minor', v_balance)
      );
    end if;

    update payments.wallet_accounts
    set available_balance_minor = 0,
        pending_balance_minor = 0,
        metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
          'test_mode', true,
          'fictitious', true,
          'launch_reset', true,
          'launch_reset_migration', '422_zero_all_test_balances_for_launch',
          'launch_reset_at', now()
        ),
        updated_at = now()
    where id = v_wallet.id;
  end loop;
end
$reset$;

commit;
