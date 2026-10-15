-- Provision the three approved ecosystem test personas with one app-scoped
-- wallet per product. Amounts are stored in minor units (20,000 MZN).
-- This script is idempotent: reruns adjust each wallet to the target balance.

do $provision$
declare
  v_item record;
  v_wallet_id uuid;
  v_old_balance bigint;
  v_target_balance constant bigint := 2000000;
  v_delta bigint;
begin
  for v_item in
    select *
    from (values
      ('5e5abc60-ecf5-416b-87a8-93cc0f30035a'::uuid, '841130015', 'deligo',   'user'),
      ('5e5abc60-ecf5-416b-87a8-93cc0f30035a'::uuid, '841130015', 'sarca',    'user'),
      ('5e5abc60-ecf5-416b-87a8-93cc0f30035a'::uuid, '841130015', 'taomoz',   'user'),
      ('5e5abc60-ecf5-416b-87a8-93cc0f30035a'::uuid, '841130015', 'comunhao', 'user'),
      ('5e5abc60-ecf5-416b-87a8-93cc0f30035a'::uuid, '841130015', 'mestre24', 'user'),
      ('0efc4ae3-9b17-4695-940c-9c68b9473e12'::uuid, '827688695', 'deligo',   'merchant'),
      ('0efc4ae3-9b17-4695-940c-9c68b9473e12'::uuid, '827688695', 'sarca',    'user'),
      ('0efc4ae3-9b17-4695-940c-9c68b9473e12'::uuid, '827688695', 'taomoz',   'seller'),
      ('0efc4ae3-9b17-4695-940c-9c68b9473e12'::uuid, '827688695', 'comunhao', 'church'),
      ('0efc4ae3-9b17-4695-940c-9c68b9473e12'::uuid, '827688695', 'mestre24', 'merchant'),
      ('8c772bb5-1f35-47f8-93ca-d6e2c8909b4d'::uuid, '877688695', 'deligo',   'driver'),
      ('8c772bb5-1f35-47f8-93ca-d6e2c8909b4d'::uuid, '877688695', 'sarca',    'driver'),
      ('8c772bb5-1f35-47f8-93ca-d6e2c8909b4d'::uuid, '877688695', 'taomoz',   'driver'),
      ('8c772bb5-1f35-47f8-93ca-d6e2c8909b4d'::uuid, '877688695', 'comunhao', 'user'),
      ('8c772bb5-1f35-47f8-93ca-d6e2c8909b4d'::uuid, '877688695', 'mestre24', 'merchant')
    ) as x(owner_user_id, phone_suffix, app_slug, account_type)
  loop
    select w.id, w.available_balance_minor
      into v_wallet_id, v_old_balance
    from payments.wallet_accounts w
    join core.apps a on a.id = w.app_id
    where w.owner_user_id = v_item.owner_user_id
      and a.slug = v_item.app_slug
      and w.currency_code = 'MZN'
    order by w.created_at
    limit 1
    for update of w;

    if v_wallet_id is null then
      insert into payments.wallet_accounts (
        owner_user_id, app_id, account_code, account_type, currency_code,
        available_balance_minor, pending_balance_minor, status, metadata
      )
      select
        v_item.owner_user_id, a.id,
        'TEST-' || upper(v_item.app_slug) || '-' || v_item.phone_suffix,
        v_item.account_type, 'MZN', 0, 0, 'active',
        jsonb_build_object('test_mode', true, 'fictitious', true,
          'persona_phone', '+258' || v_item.phone_suffix,
          'provisioning_source', 'ecosystem_test_personas_395')
      from core.apps a
      where a.slug = v_item.app_slug
      returning id, available_balance_minor into v_wallet_id, v_old_balance;
    end if;

    if v_wallet_id is null then
      raise exception 'Core app not found: %', v_item.app_slug;
    end if;

    v_delta := v_target_balance - coalesce(v_old_balance, 0);

    update payments.wallet_accounts
    set account_type = v_item.account_type,
        available_balance_minor = v_target_balance,
        pending_balance_minor = 0,
        status = 'active',
        metadata = metadata || jsonb_build_object(
          'test_mode', true, 'fictitious', true,
          'persona_phone', '+258' || v_item.phone_suffix,
          'target_balance_minor', v_target_balance,
          'provisioning_source', 'ecosystem_test_personas_395'),
        updated_at = now()
    where id = v_wallet_id;

    if v_delta <> 0 then
      insert into payments.wallet_ledger_entries (
        wallet_account_id, app_id, entry_side, entry_type, currency_code,
        amount_minor, balance_after_minor, reference_type, reference_id,
        description, metadata
      )
      select
        v_wallet_id, a.id,
        case when v_delta > 0 then 'credit' else 'debit' end,
        'test_balance_adjustment', 'MZN', abs(v_delta), v_target_balance,
        'ecosystem_test_persona',
        'TEST-' || v_item.app_slug || '-' || v_item.phone_suffix || '-20000',
        'Saldo ficticio para testes internos do ecossistema DeliGo Triunfa',
        jsonb_build_object('test_mode', true, 'fictitious', true,
          'persona_phone', '+258' || v_item.phone_suffix,
          'previous_balance_minor', coalesce(v_old_balance, 0),
          'target_balance_minor', v_target_balance,
          'provisioning_source', 'ecosystem_test_personas_395')
      from core.apps a
      where a.slug = v_item.app_slug;
    end if;
  end loop;
end
$provision$;
