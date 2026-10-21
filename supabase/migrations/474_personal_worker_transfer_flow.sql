begin;

-- O levantamento interno aprovado termina sempre na carteira pessoal do
-- administrador que abriu o pedido. O Finance apenas confirma com OTP.
create or replace function public.hq_transfer_approved_profit_v1(p_withdrawal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, hq, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_withdrawal public.admin_corporate_withdrawals%rowtype;
  v_approval public.admin_corporate_withdrawal_approvals%rowtype;
  v_source hq.logical_wallets%rowtype;
  v_destination hq.logical_wallets%rowtype;
  v_requester_employee_id uuid;
  v_approver_employee_id uuid;
  v_amount numeric;
  v_operation uuid;
begin
  if v_actor is null then raise exception 'authentication_required'; end if;
  select * into v_withdrawal from public.admin_corporate_withdrawals where id = p_withdrawal_id for update;
  if v_withdrawal.id is null then raise exception 'withdrawal_not_found'; end if;
  if v_withdrawal.status = 'reserved' then
    return jsonb_build_object('ok', true, 'withdrawal_id', v_withdrawal.id, 'status', 'reserved');
  end if;
  if v_withdrawal.status <> 'approved' or v_withdrawal.approval_status <> 'approved' then raise exception 'second_approval_required'; end if;
  select * into v_approval from public.admin_corporate_withdrawal_approvals
    where withdrawal_id = v_withdrawal.id and status = 'verified' order by verified_at desc limit 1 for update;
  if v_approval.id is null then raise exception 'verified_second_approval_not_found'; end if;
  if v_withdrawal.second_approver_id is distinct from v_approval.approver_id then raise exception 'second_approver_mismatch'; end if;
  select id into v_requester_employee_id from hq.employees where auth_user_id = v_withdrawal.admin_id and status = 'active' order by created_at limit 1;
  select id into v_approver_employee_id from hq.employees where auth_user_id = v_approval.approver_id and status = 'active' order by created_at limit 1;
  if v_requester_employee_id is null then raise exception 'requester_employee_not_found'; end if;
  if v_approver_employee_id is null then raise exception 'approver_employee_not_found'; end if;
  v_amount := round(v_withdrawal.amount, 2);
  select * into v_source from hq.logical_wallets
    where wallet_code = 'CORPORATE_MZN' and currency = 'MZN' and status = 'active' order by created_at limit 1 for update;
  if v_source.id is null then raise exception 'corporate_wallet_not_found'; end if;
  if v_source.available_amount < v_amount then raise exception 'corporate_wallet_insufficient'; end if;

  -- A origem é CORPORATE_MZN; o destino é o Admin que solicitou o levantamento,
  -- nunca o Finance que apenas confirmou o OTP.
  select * into v_destination from hq.logical_wallets
    where owner_user_id = v_withdrawal.admin_id and wallet_type = 'employee' and status = 'active' and currency = 'MZN'
    order by created_at limit 1 for update;
  if v_destination.id is null then raise exception 'employee_wallet_not_found'; end if;
  update hq.logical_wallets set available_amount = available_amount - v_amount, updated_at = now() where id = v_source.id;
  update hq.logical_wallets set available_amount = available_amount + v_amount, updated_at = now() where id = v_destination.id;
  insert into hq.ledger_operations (
    wallet_from, wallet_to, amount, currency, operation_type, reference_id, status,
    requested_by, approved_by, executed_by, second_approved_by, metadata, approved_at, executed_at
  ) values (
    v_source.id, v_destination.id, v_amount, 'MZN', 'INTERNAL_TRANSFER', v_withdrawal.id::text, 'settled',
    v_requester_employee_id, v_approver_employee_id, v_requester_employee_id, v_approver_employee_id,
    jsonb_build_object('purpose', 'approved_corporate_profit_to_requesting_admin', 'withdrawal_id', v_withdrawal.id,
      'approval_id', v_approval.id, 'second_approver_id', v_approval.approver_id), now(), now()
  ) returning id into v_operation;
  update public.admin_corporate_withdrawals set status = 'reserved', updated_at = now() where id = v_withdrawal.id;
  update public.admin_corporate_withdrawal_approvals set status = 'consumed', consumed_at = now(), updated_at = now()
    where id = v_approval.id and status = 'verified';
  return jsonb_build_object('ok', true, 'withdrawal_id', v_withdrawal.id, 'ledger_operation_id', v_operation,
    'amount', v_amount, 'status', 'reserved', 'requested_by', v_requester_employee_id, 'approved_by', v_approver_employee_id,
    'destination_user_id', v_withdrawal.admin_id);
end;
$$;
revoke all on function public.hq_transfer_approved_profit_v1(uuid) from public, anon;
grant execute on function public.hq_transfer_approved_profit_v1(uuid) to authenticated, service_role;

create table if not exists payments.employee_personal_transfers (
  id uuid primary key default gen_random_uuid(),
  idempotency_key text not null unique,
  actor_auth_user_id uuid not null references auth.users(id) on delete restrict,
  target_employee_id uuid not null references hq.employees(id) on delete restrict,
  target_auth_user_id uuid not null references auth.users(id) on delete restrict,
  source_wallet_id uuid not null references payments.wallet_accounts(id) on delete restrict,
  destination_wallet_id uuid not null references payments.wallet_accounts(id) on delete restrict,
  amount numeric(18,2) not null check (amount > 0),
  currency text not null default 'MZN',
  status text not null default 'settled' check (status in ('settled','reversed')),
  payment_transaction_id uuid references payments.payment_transactions(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index if not exists employee_personal_transfers_target_idx on payments.employee_personal_transfers(target_employee_id, created_at desc);
alter table payments.employee_personal_transfers enable row level security;
revoke all on payments.employee_personal_transfers from public, anon, authenticated;
grant all on payments.employee_personal_transfers to service_role;

create or replace function public.hq_transfer_employee_personal_to_worker_v1(
  p_actor_auth_user_id uuid, p_target_employee_id uuid, p_amount numeric, p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path = public, hq, payments, pg_temp
as $$
declare
  v_actor hq.employees%rowtype;
  v_target hq.employees%rowtype;
  v_source payments.wallet_accounts%rowtype;
  v_destination payments.wallet_accounts%rowtype;
  v_existing payments.employee_personal_transfers%rowtype;
  v_transfer_id uuid := gen_random_uuid();
  v_payment_transaction uuid;
  v_amount numeric(18,2) := round(p_amount, 2);
  v_minor bigint := round(v_amount * 100)::bigint;
  v_reference text := 'HQ-PERSONAL-TRANSFER:' || v_transfer_id::text;
begin
  if p_actor_auth_user_id is null or p_target_employee_id is null then raise exception 'transfer_identity_required'; end if;
  if nullif(btrim(coalesce(p_idempotency_key, '')), '') is null then raise exception 'transfer_idempotency_required'; end if;
  if v_amount is null or v_amount <= 0 then raise exception 'invalid_transfer_amount'; end if;
  if not exists (select 1 from public.user_roles r where r.user_id = p_actor_auth_user_id and r.role::text in ('SUPER_ADMIN', 'FINANCE')) then
    raise exception 'finance_transfer_role_required';
  end if;
  select * into v_existing from payments.employee_personal_transfers where idempotency_key = btrim(p_idempotency_key) limit 1;
  if v_existing.id is not null then
    return jsonb_build_object('ok', true, 'transfer_id', v_existing.id, 'status', v_existing.status, 'amount', v_existing.amount,
      'currency', v_existing.currency, 'target_employee_id', v_existing.target_employee_id, 'idempotent_replay', true);
  end if;
  select * into v_actor from hq.employees where auth_user_id = p_actor_auth_user_id and status = 'active' order by created_at limit 1;
  if v_actor.id is null then raise exception 'actor_employee_not_found'; end if;
  select * into v_target from hq.employees where id = p_target_employee_id and status = 'active';
  if v_target.id is null or v_target.auth_user_id is null then raise exception 'target_employee_not_found'; end if;
  if v_target.auth_user_id = p_actor_auth_user_id then raise exception 'target_must_be_another_worker'; end if;
  select * into v_source from payments.wallet_accounts where owner_user_id = p_actor_auth_user_id and app_id is null
    and account_type = 'user' and currency_code = 'MZN' and status = 'active' order by created_at limit 1 for update;
  if v_source.id is null then raise exception 'source_personal_wallet_not_found'; end if;
  if coalesce(v_source.available_balance_minor, 0) < v_minor then raise exception 'personal_wallet_insufficient'; end if;
  select * into v_destination from payments.wallet_accounts where owner_user_id = v_target.auth_user_id and app_id is null
    and account_type = 'user' and currency_code = 'MZN' and status = 'active' order by created_at limit 1 for update;
  if v_destination.id is null then
    insert into payments.wallet_accounts (owner_user_id, app_id, account_code, account_type, currency_code, available_balance_minor, pending_balance_minor, status, metadata)
      values (v_target.auth_user_id, null, 'HQ-EMPLOYEE-' || v_target.id::text, 'user', 'MZN', 0, 0, 'active', jsonb_build_object('provider_integration', 'paysuite', 'source', 'employee_personal_transfer'))
      returning * into v_destination;
  end if;
  update payments.wallet_accounts set available_balance_minor = available_balance_minor - v_minor, updated_at = now() where id = v_source.id;
  update payments.wallet_accounts set available_balance_minor = available_balance_minor + v_minor, updated_at = now() where id = v_destination.id;
  insert into payments.payment_transactions (app_id, initiator_user_id, wallet_account_id, transaction_type, status, funds_status, amount_minor, fee_minor, external_reference, metadata, settled_at)
    values (null, p_actor_auth_user_id, v_destination.id, 'transfer', 'settled', 'released', v_minor, 0, v_reference,
      jsonb_build_object('source', 'employee_personal_wallet', 'source_wallet_id', v_source.id, 'target_employee_id', v_target.id), now()) returning id into v_payment_transaction;
  insert into payments.wallet_ledger_entries (wallet_account_id, app_id, entry_side, entry_type, currency_code, amount_minor, balance_after_minor, reference_type, reference_id, counterparty_wallet_account_id, payment_transaction_id, description, metadata)
    select v_source.id, v_source.app_id, 'debit', 'transfer', v_source.currency_code, v_minor, v_source.available_balance_minor, 'employee_personal_transfer', v_transfer_id::text, v_destination.id, v_payment_transaction,
      'Transferência pessoal enviada a trabalhador', jsonb_build_object('target_employee_id', v_target.id, 'destination_wallet_id', v_destination.id);
  insert into payments.wallet_ledger_entries (wallet_account_id, app_id, entry_side, entry_type, currency_code, amount_minor, balance_after_minor, reference_type, reference_id, counterparty_wallet_account_id, payment_transaction_id, description, metadata)
    select v_destination.id, v_destination.app_id, 'credit', 'transfer', v_destination.currency_code, v_minor, v_destination.available_balance_minor, 'employee_personal_transfer', v_transfer_id::text, v_source.id, v_payment_transaction,
      'Transferência pessoal recebida de trabalhador', jsonb_build_object('actor_auth_user_id', p_actor_auth_user_id, 'source_wallet_id', v_source.id);
  insert into payments.employee_personal_transfers (id, idempotency_key, actor_auth_user_id, target_employee_id, target_auth_user_id, source_wallet_id, destination_wallet_id, amount, currency, payment_transaction_id)
    values (v_transfer_id, btrim(p_idempotency_key), p_actor_auth_user_id, v_target.id, v_target.auth_user_id, v_source.id, v_destination.id, v_amount, 'MZN', v_payment_transaction);
  perform public.create_app_notification(p_user_id := v_target.auth_user_id, p_type := 'HQ_EMPLOYEE_PERSONAL_TRANSFER', p_title := 'Transferência recebida', p_body := 'Recebeu uma transferência pessoal de um trabalhador da Central.', p_action := 'wallet', p_entity_id := v_transfer_id::text, p_priority := 'HIGH', p_channel := 'system', p_metadata := jsonb_build_object('amount', v_amount, 'currency', 'MZN', 'source', 'employee_personal_wallet'));
  return jsonb_build_object('ok', true, 'transfer_id', v_transfer_id, 'status', 'settled', 'amount', v_amount, 'currency', 'MZN', 'target_employee_id', v_target.id, 'payment_transaction_id', v_payment_transaction);
end;
$$;
revoke all on function public.hq_transfer_employee_personal_to_worker_v1(uuid, uuid, numeric, text) from public, anon, authenticated;
grant execute on function public.hq_transfer_employee_personal_to_worker_v1(uuid, uuid, numeric, text) to service_role;

-- Impede que qualquer cliente antigo volte a enviar diretamente da carteira corporativa para um trabalhador.
create or replace function public.hq_transfer_corporate_to_employee_v1(uuid, uuid, numeric, text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  raise exception 'direct_corporate_to_employee_disabled';
end;
$$;
revoke all on function public.hq_transfer_corporate_to_employee_v1(uuid, uuid, numeric, text) from public, anon, authenticated;
grant execute on function public.hq_transfer_corporate_to_employee_v1(uuid, uuid, numeric, text) to service_role;

notify pgrst, 'reload schema';
commit;
