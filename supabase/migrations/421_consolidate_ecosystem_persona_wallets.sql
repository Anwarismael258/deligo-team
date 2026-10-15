-- Consolidate the ecosystem personas into one central wallet per person.
-- This migration is intentionally additive and append-only: no ledger rows are
-- deleted. It must be applied only after the remote migration history is synced.

begin;

do $consolidate$
declare
  v_persona record;
  v_wallet record;
  v_global_id uuid;
  v_retired_id uuid;
  v_old_total bigint;
  v_target constant bigint := 2000000; -- 20,000.00 MZN
begin
  -- Non-spendable internal retirement account for balances removed from the
  -- old app-scoped test wallets. It is not a user wallet and cannot withdraw.
  insert into payments.wallet_accounts (
    owner_user_id, app_id, account_code, account_type, currency_code,
    available_balance_minor, pending_balance_minor, status, metadata
  ) values (
    null, null, 'CENTRAL-INTERNAL-RETIRED-ECOSYSTEM', 'system', 'MZN',
    0, 0, 'active', jsonb_build_object(
      'internal_only', true,
      'withdrawal_disabled', true,
      'purpose', 'retired_ecosystem_persona_balances',
      'migration', '421_consolidate_ecosystem_persona_wallets'
    )
  )
  on conflict (account_code) do update set
    metadata = payments.wallet_accounts.metadata || excluded.metadata,
    updated_at = now()
  returning id into v_retired_id;

  for v_persona in
    select * from (values
      ('5e5abc60-ecf5-416b-87a8-93cc0f30035a'::uuid, '841130015'),
      ('0efc4ae3-9b17-4695-940c-9c68b9473e12'::uuid, '827688695'),
      ('8c772bb5-1f35-47f8-93ca-d6e2c8909b4d'::uuid, '877688695')
    ) as p(owner_user_id, phone_suffix)
  loop
    insert into payments.wallet_accounts (
      owner_user_id, app_id, account_code, account_type, currency_code,
      available_balance_minor, pending_balance_minor, status, metadata
    ) values (
      v_persona.owner_user_id, null,
      'CENTRAL-USER-' || v_persona.phone_suffix, 'user', 'MZN',
      v_target, 0, 'active', jsonb_build_object(
        'persona_phone', '+258' || v_persona.phone_suffix,
        'internal_only', true,
        'withdrawal_disabled', true,
        'internal_transfer_enabled', true,
        'payroll_enabled', true,
        'provider_integration', 'pending',
        'provisioning_source', 'ecosystem_persona_consolidation_421'
      )
    )
    on conflict (account_code) do update set
      owner_user_id = excluded.owner_user_id,
      app_id = null,
      account_type = 'user',
      currency_code = 'MZN',
      available_balance_minor = v_target,
      pending_balance_minor = 0,
      status = 'active',
      metadata = payments.wallet_accounts.metadata || excluded.metadata,
      updated_at = now()
    returning id into v_global_id;

    -- Retire every old platform-scoped wallet for this person. Ledger history
    -- remains intact; only the spendable cached balance is closed out.
    for v_wallet in
      select id, available_balance_minor, pending_balance_minor
      from payments.wallet_accounts
      where owner_user_id = v_persona.owner_user_id
        and app_id is not null
        and currency_code = 'MZN'
        and status <> 'closed'
      for update
    loop
      v_old_total := coalesce(v_wallet.available_balance_minor, 0)
        + coalesce(v_wallet.pending_balance_minor, 0);

      if v_old_total > 0 then
        insert into payments.wallet_ledger_entries (
          wallet_account_id, entry_side, entry_type, currency_code,
          amount_minor, balance_after_minor, reference_type, reference_id,
          description, metadata
        ) values (
          v_wallet.id, 'debit', 'internal_balance_retirement', 'MZN',
          v_old_total, 0, 'wallet_consolidation',
          '421-' || v_persona.phone_suffix,
          'Encerramento de saldo por consolidação em carteira central',
          jsonb_build_object('internal_only', true, 'withdrawal_disabled', true,
            'destination_wallet_id', v_retired_id)
        );

        insert into payments.wallet_ledger_entries (
          wallet_account_id, entry_side, entry_type, currency_code,
          amount_minor, balance_after_minor, reference_type, reference_id,
          description, metadata
        ) values (
          v_retired_id, 'credit', 'internal_balance_retirement', 'MZN',
          v_old_total, null, 'wallet_consolidation',
          '421-' || v_persona.phone_suffix,
          'Saldo retirado de carteiras por plataforma; sem levantamento externo',
          jsonb_build_object('internal_only', true, 'withdrawal_disabled', true,
            'source_wallet_id', v_wallet.id)
        );
      end if;

      update payments.wallet_accounts
      set available_balance_minor = 0,
          pending_balance_minor = 0,
          status = 'closed',
          metadata = metadata || jsonb_build_object(
            'consolidated_into_wallet_id', v_global_id,
            'internal_only', true,
            'withdrawal_disabled', true,
            'closed_by_migration', '421_consolidate_ecosystem_persona_wallets'
          ),
          updated_at = now()
      where id = v_wallet.id;
    end loop;
  end loop;
end
$consolidate$;

commit;
