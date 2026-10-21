-- Move only the authenticated worker's real legacy personal wallet into the
-- canonical PaySuite wallet before a personal withdrawal. This never reads
-- corporate aggregates or unassigned payment totals.
begin;

create or replace function public.migrate_legacy_personal_wallet_to_paysuite_v1(
  p_auth_user_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, payments, pg_temp
as $$
declare
  v_legacy public.wallets%rowtype;
  v_destination payments.wallet_accounts%rowtype;
  v_before numeric(18,2);
  v_amount numeric(18,2);
  v_amount_minor bigint;
  v_reference text;
begin
  if p_auth_user_id is null then
    raise exception 'legacy_wallet_identity_required';
  end if;

  select * into v_legacy
  from public.wallets
  where user_id = p_auth_user_id
    and coalesce(currency, 'MZN') = 'MZN'
    and coalesce(is_active, true)
  order by coalesce(is_default, false) desc, updated_at desc nulls last, created_at asc
  limit 1
  for update;

  if v_legacy.id is null or coalesce(v_legacy.balance, 0) <= 0 then
    return jsonb_build_object('ok', true, 'migrated', false, 'amount', 0, 'currency', 'MZN');
  end if;

  v_amount := round(v_legacy.balance::numeric, 2);
  v_amount_minor := round(v_amount * 100)::bigint;
  v_reference := 'legacy-personal-wallet-migration:' || v_legacy.id::text;

  if exists (select 1 from public.wallet_ledger where reference_key = v_reference) then
    return jsonb_build_object('ok', true, 'migrated', false, 'already_migrated', true, 'amount', v_amount, 'currency', 'MZN');
  end if;

  select * into v_destination
  from payments.wallet_accounts
  where owner_user_id = p_auth_user_id
    and app_id is null
    and account_type = 'user'
    and currency_code = 'MZN'
    and status = 'active'
  order by created_at
  limit 1
  for update;

  if v_destination.id is null then
    insert into payments.wallet_accounts (
      owner_user_id, app_id, account_code, account_type, currency_code,
      available_balance_minor, pending_balance_minor, reserved_balance_minor,
      status, metadata
    ) values (
      p_auth_user_id, null, 'HQ-LEGACY-' || p_auth_user_id::text, 'user', 'MZN',
      0, 0, 0, 'active',
      jsonb_build_object('provider_integration', 'paysuite', 'withdrawal_disabled', false, 'source', 'legacy_personal_wallet_migration')
    ) returning * into v_destination;
  end if;

  v_before := coalesce(v_destination.available_balance_minor, 0)::numeric / 100;

  update public.wallets
  set balance = 0, updated_at = now()
  where id = v_legacy.id;

  update payments.wallet_accounts
  set available_balance_minor = coalesce(available_balance_minor, 0) + v_amount_minor,
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('provider_integration', 'paysuite', 'withdrawal_disabled', false, 'source', 'legacy_personal_wallet_migration'),
      updated_at = now()
  where id = v_destination.id;

  insert into public.wallet_ledger (
    wallet_id, user_id, direction, entry_type, amount, balance_before, balance_after,
    metadata, reference_key, status
  ) values (
    v_legacy.id, p_auth_user_id, 'debit', 'legacy_wallet_migration', v_amount,
    v_amount, 0, jsonb_build_object('destination_wallet_id', v_destination.id, 'source', 'legacy_personal_wallet_migration'),
    v_reference, 'confirmed'
  );

  insert into payments.wallet_ledger_entries (
    wallet_account_id, entry_side, entry_type, currency_code, amount_minor,
    balance_after_minor, reference_type, reference_id, description, metadata
  )
  select v_destination.id, 'credit', 'legacy_wallet_migration', 'MZN', v_amount_minor,
    available_balance_minor, 'legacy_wallet_migration', v_reference,
    'Migração do saldo pessoal DeliGo para a carteira PaySuite',
    jsonb_build_object('source', 'legacy_personal_wallet', 'legacy_wallet_id', v_legacy.id)
  from payments.wallet_accounts
  where id = v_destination.id;

  return jsonb_build_object(
    'ok', true, 'migrated', true, 'amount', v_amount, 'currency', 'MZN',
    'destination_wallet_id', v_destination.id, 'reference', v_reference
  );
end;
$$;

revoke all on function public.migrate_legacy_personal_wallet_to_paysuite_v1(uuid) from public, anon, authenticated;
grant execute on function public.migrate_legacy_personal_wallet_to_paysuite_v1(uuid) to service_role;
notify pgrst, 'reload schema';
commit;
