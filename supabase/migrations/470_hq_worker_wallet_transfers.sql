-- Transferências internas da carteira corporativa para carteiras pessoais de trabalhadores.
-- A operação é atómica, idempotente e só pode ser iniciada por SUPER_ADMIN ou FINANCE.
begin;

create table if not exists hq.employee_wallet_transfers (
  id uuid primary key default gen_random_uuid(),
  idempotency_key text not null unique,
  actor_auth_user_id uuid not null references auth.users(id) on delete restrict,
  actor_employee_id uuid references hq.employees(id) on delete set null,
  target_employee_id uuid not null references hq.employees(id) on delete restrict,
  target_auth_user_id uuid not null references auth.users(id) on delete restrict,
  source_wallet_id uuid not null references hq.logical_wallets(id) on delete restrict,
  destination_wallet_id uuid not null references payments.wallet_accounts(id) on delete restrict,
  amount numeric(18,2) not null check (amount > 0),
  currency text not null default 'MZN',
  status text not null default 'settled' check (status in ('settled','reversed')),
  hq_operation_id uuid references hq.ledger_operations(id) on delete restrict,
  payment_transaction_id uuid references payments.payment_transactions(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index if not exists hq_employee_wallet_transfers_target_idx
  on hq.employee_wallet_transfers(target_employee_id, created_at desc);

alter table hq.employee_wallet_transfers enable row level security;
revoke all on hq.employee_wallet_transfers from public, anon, authenticated;
grant all on hq.employee_wallet_transfers to service_role;

create or replace function public.hq_transfer_corporate_to_employee_v1(
  p_actor_auth_user_id uuid,
  p_target_employee_id uuid,
  p_amount numeric,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = public, hq, payments, pg_temp
as $$
declare
  v_actor hq.employees%rowtype;
  v_target hq.employees%rowtype;
  v_source hq.logical_wallets%rowtype;
  v_destination payments.wallet_accounts%rowtype;
  v_existing hq.employee_wallet_transfers%rowtype;
  v_transfer_id uuid := gen_random_uuid();
  v_hq_operation uuid;
  v_payment_transaction uuid;
  v_amount numeric(18,2) := round(p_amount, 2);
  v_reference text := 'HQ-EMPLOYEE-TRANSFER:' || v_transfer_id::text;
begin
  if p_actor_auth_user_id is null or p_target_employee_id is null then
    raise exception 'transfer_identity_required';
  end if;
  if nullif(btrim(coalesce(p_idempotency_key, '')), '') is null then
    raise exception 'transfer_idempotency_required';
  end if;
  if v_amount is null or v_amount <= 0 then
    raise exception 'invalid_transfer_amount';
  end if;

  if not exists (
    select 1 from public.user_roles r
    where r.user_id = p_actor_auth_user_id
      and r.role::text in ('SUPER_ADMIN', 'FINANCE')
  ) then
    raise exception 'finance_transfer_role_required';
  end if;

  select * into v_existing
  from hq.employee_wallet_transfers
  where idempotency_key = btrim(p_idempotency_key)
  limit 1;
  if v_existing.id is not null then
    return jsonb_build_object(
      'ok', true, 'transfer_id', v_existing.id, 'status', v_existing.status,
      'amount', v_existing.amount, 'currency', v_existing.currency,
      'target_employee_id', v_existing.target_employee_id,
      'destination_wallet_id', v_existing.destination_wallet_id,
      'idempotent_replay', true
    );
  end if;

  select * into v_actor from hq.employees
  where auth_user_id = p_actor_auth_user_id and status = 'active'
  order by created_at limit 1;
  if v_actor.id is null then raise exception 'actor_employee_not_found'; end if;

  select * into v_target from hq.employees
  where id = p_target_employee_id and status = 'active';
  if v_target.id is null or v_target.auth_user_id is null then
    raise exception 'target_employee_not_found';
  end if;
  if v_target.auth_user_id = p_actor_auth_user_id then
    raise exception 'target_must_be_another_worker';
  end if;

  select * into v_source
  from hq.logical_wallets
  where wallet_code = 'CORPORATE_MZN' and currency = 'MZN' and status = 'active'
  order by created_at limit 1 for update;
  if v_source.id is null then raise exception 'corporate_wallet_not_found'; end if;
  if v_source.available_amount < v_amount then raise exception 'corporate_wallet_insufficient'; end if;

  select * into v_destination
  from payments.wallet_accounts
  where owner_user_id = v_target.auth_user_id
    and app_id is null and account_type = 'user' and currency_code = 'MZN'
    and status = 'active'
  order by created_at limit 1 for update;

  if v_destination.id is null then
    insert into payments.wallet_accounts (
      owner_user_id, app_id, account_code, account_type, currency_code,
      available_balance_minor, pending_balance_minor, status, metadata
    ) values (
      v_target.auth_user_id, null, 'HQ-EMPLOYEE-' || v_target.id::text,
      'user', 'MZN', 0, 0, 'active',
      jsonb_build_object('provider_integration', 'paysuite', 'withdrawal_disabled', false, 'source', 'hq_employee_transfer')
    ) returning * into v_destination;
  else
    update payments.wallet_accounts
    set metadata = metadata || jsonb_build_object('provider_integration', 'paysuite', 'withdrawal_disabled', false),
        updated_at = now()
    where id = v_destination.id
    returning * into v_destination;
  end if;

  update hq.logical_wallets
  set available_amount = available_amount - v_amount, updated_at = now()
  where id = v_source.id;

  insert into hq.ledger_operations (
    wallet_from, wallet_to, amount, currency, operation_type, reference_id,
    status, requested_by, approved_by, executed_by, metadata,
    requested_at, approved_at, executed_at
  ) values (
    v_source.id, null, v_amount, 'MZN', 'INTERNAL_TRANSFER', v_reference,
    'settled', v_actor.id, v_actor.id, v_actor.id,
    jsonb_build_object(
      'purpose', 'corporate_to_employee_wallet',
      'target_employee_id', v_target.id,
      'target_auth_user_id', v_target.auth_user_id,
      'destination_wallet_id', v_destination.id,
      'idempotency_key', btrim(p_idempotency_key)
    ), now(), now(), now()
  ) returning id into v_hq_operation;

  update payments.wallet_accounts
  set available_balance_minor = available_balance_minor + (v_amount * 100)::bigint,
      updated_at = now()
  where id = v_destination.id;

  insert into payments.payment_transactions (
    app_id, initiator_user_id, wallet_account_id, transaction_type, status,
    funds_status, amount_minor, fee_minor, external_reference, metadata, settled_at
  ) values (
    null, p_actor_auth_user_id, v_destination.id, 'transfer', 'settled', 'released',
    (v_amount * 100)::bigint, 0, v_reference,
    jsonb_build_object('source', 'hq_corporate_wallet', 'hq_operation_id', v_hq_operation, 'target_employee_id', v_target.id), now()
  ) returning id into v_payment_transaction;

  insert into payments.wallet_ledger_entries (
    wallet_account_id, entry_side, entry_type, currency_code, amount_minor,
    balance_after_minor, reference_type, reference_id, counterparty_wallet_account_id,
    payment_transaction_id, description, metadata
  )
  select v_destination.id, 'credit', 'hq_employee_transfer', 'MZN', (v_amount * 100)::bigint,
    available_balance_minor, 'hq_employee_wallet_transfer', v_transfer_id::text, null,
    v_payment_transaction, 'Transferência recebida da carteira corporativa',
    jsonb_build_object('hq_operation_id', v_hq_operation, 'actor_employee_id', v_actor.id, 'source_wallet_id', v_source.id)
  from payments.wallet_accounts where id = v_destination.id;

  insert into hq.employee_wallet_transfers (
    id, idempotency_key, actor_auth_user_id, actor_employee_id, target_employee_id,
    target_auth_user_id, source_wallet_id, destination_wallet_id, amount, currency,
    status, hq_operation_id, payment_transaction_id
  ) values (
    v_transfer_id, btrim(p_idempotency_key), p_actor_auth_user_id, v_actor.id, v_target.id,
    v_target.auth_user_id, v_source.id, v_destination.id, v_amount, 'MZN',
    'settled', v_hq_operation, v_payment_transaction
  );

  perform public.create_app_notification(
    p_user_id := v_target.auth_user_id,
    p_type := 'HQ_EMPLOYEE_WALLET_TRANSFER',
    p_title := 'Transferência recebida',
    p_body := 'A Central transferiu saldo para a sua carteira pessoal.',
    p_action := 'wallet',
    p_entity_id := v_transfer_id::text,
    p_priority := 'HIGH',
    p_channel := 'system',
    p_metadata := jsonb_build_object('amount', v_amount, 'currency', 'MZN', 'source', 'hq_corporate_wallet')
  );

  return jsonb_build_object(
    'ok', true, 'transfer_id', v_transfer_id, 'status', 'settled',
    'amount', v_amount, 'currency', 'MZN', 'target_employee_id', v_target.id,
    'destination_wallet_id', v_destination.id, 'hq_operation_id', v_hq_operation,
    'payment_transaction_id', v_payment_transaction
  );
end;
$$;

revoke all on function public.hq_transfer_corporate_to_employee_v1(uuid, uuid, numeric, text) from public, anon, authenticated;
grant execute on function public.hq_transfer_corporate_to_employee_v1(uuid, uuid, numeric, text) to service_role;

notify pgrst, 'reload schema';
commit;
