begin;

-- PaySuite payouts from the employee wallet created by the HQ corporate-profit
-- transfer. The amount is reserved before the provider call and is only
-- removed from the wallet after a success callback/provider response.
create or replace function public.hq_prepare_employee_paysuite_payout_v1(
  p_actor_auth_user_id uuid,
  p_amount numeric,
  p_method text,
  p_phone_number text,
  p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path = public, hq, pg_temp
as $$
declare
  v_employee hq.employees%rowtype;
  v_wallet hq.logical_wallets%rowtype;
  v_request hq.payout_requests%rowtype;
  v_amount numeric := round(coalesce(p_amount, 0), 2);
  v_provider text := case when lower(coalesce(p_method, 'mpesa')) = 'emola' then 'movitel' else 'vodacom_mpesa' end;
  v_reference text := 'DLG-HQ-PAYOUT-' || replace(gen_random_uuid()::text, '-', '');
begin
  if p_actor_auth_user_id is null then raise exception 'authentication_required'; end if;
  if v_amount <= 0 then raise exception 'invalid_payout_amount'; end if;
  if nullif(btrim(coalesce(p_idempotency_key, '')), '') is null then raise exception 'payout_idempotency_required'; end if;

  select * into v_request from hq.payout_requests where idempotency_key = btrim(p_idempotency_key) limit 1;
  if v_request.id is not null then
    return jsonb_build_object('ok', true, 'payout_request_id', v_request.id, 'reference', v_request.metadata->>'reference', 'status', v_request.status, 'amount', v_request.amount, 'idempotent', true);
  end if;

  select * into v_employee from hq.employees where auth_user_id = p_actor_auth_user_id and status = 'active' order by created_at limit 1;
  if v_employee.id is null then raise exception 'employee_not_found'; end if;
  select * into v_wallet from hq.logical_wallets where owner_user_id = p_actor_auth_user_id and wallet_type = 'employee' and status = 'active' and currency = 'MZN' order by created_at limit 1 for update;
  if v_wallet.id is null then raise exception 'employee_wallet_not_found'; end if;
  if coalesce(v_wallet.available_amount, 0) < v_amount then raise exception 'employee_wallet_insufficient'; end if;

  insert into hq.payout_requests (
    request_type, beneficiary_user_id, beneficiary_reference, amount, currency, provider,
    destination_number, status, idempotency_key, source_reference, metadata, requested_by
  ) values (
    'withdrawal', p_actor_auth_user_id, p_phone_number, v_amount, 'MZN', v_provider,
    p_phone_number, 'processing', btrim(p_idempotency_key), v_wallet.wallet_code,
    jsonb_build_object('reference', v_reference, 'source', 'hq_employee_wallet', 'method', p_method), v_employee.id
  ) returning * into v_request;

  update hq.logical_wallets
    set available_amount = available_amount - v_amount,
        reserved_amount = reserved_amount + v_amount,
        updated_at = now()
    where id = v_wallet.id;
  insert into hq.ledger_operations (
    wallet_from, amount, currency, operation_type, reference_id, status, requested_by,
    provider, metadata
  ) values (
    v_wallet.id, v_amount, 'MZN', 'EMPLOYEE_WITHDRAWAL', v_request.id::text, 'processing',
    v_employee.id, v_provider, jsonb_build_object('reference', v_reference, 'payout_request_id', v_request.id, 'destination', p_phone_number)
  );
  return jsonb_build_object('ok', true, 'payout_request_id', v_request.id, 'reference', v_reference, 'status', 'processing', 'amount', v_amount);
end;
$$;

create or replace function public.hq_complete_employee_paysuite_payout_v1(p_payout_request_id uuid, p_provider_reference text)
returns jsonb language plpgsql security definer set search_path = public, hq, pg_temp
as $$
declare
  v_request hq.payout_requests%rowtype;
  v_wallet hq.logical_wallets%rowtype;
begin
  select * into v_request from hq.payout_requests where id = p_payout_request_id for update;
  if v_request.id is null then raise exception 'payout_request_not_found'; end if;
  if v_request.status = 'paid' then return jsonb_build_object('ok', true, 'status', 'paid', 'idempotent', true); end if;
  select * into v_wallet from hq.logical_wallets where wallet_code = v_request.source_reference and status = 'active' for update;
  if v_wallet.id is null then raise exception 'employee_wallet_not_found'; end if;
  if coalesce(v_wallet.reserved_amount, 0) < v_request.amount then raise exception 'payout_reservation_missing'; end if;
  update hq.logical_wallets set reserved_amount = reserved_amount - v_request.amount, updated_at = now() where id = v_wallet.id;
  update hq.ledger_operations set status = 'settled', provider_reference = p_provider_reference, executed_at = coalesce(executed_at, now()), updated_at = now() where reference_id = v_request.id::text and operation_type = 'EMPLOYEE_WITHDRAWAL' and status = 'processing';
  update hq.payout_requests set status = 'paid', provider_reference = p_provider_reference, updated_at = now() where id = v_request.id;
  return jsonb_build_object('ok', true, 'status', 'paid', 'payout_request_id', v_request.id, 'provider_reference', p_provider_reference);
end;
$$;

create or replace function public.hq_fail_employee_paysuite_payout_v1(p_payout_request_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, hq, pg_temp
as $$
declare
  v_request hq.payout_requests%rowtype;
  v_wallet hq.logical_wallets%rowtype;
begin
  select * into v_request from hq.payout_requests where id = p_payout_request_id for update;
  if v_request.id is null then raise exception 'payout_request_not_found'; end if;
  if v_request.status in ('failed', 'reversed', 'cancelled') then return jsonb_build_object('ok', true, 'status', v_request.status, 'idempotent', true); end if;
  select * into v_wallet from hq.logical_wallets where wallet_code = v_request.source_reference and status = 'active' for update;
  if v_wallet.id is null then raise exception 'employee_wallet_not_found'; end if;
  update hq.logical_wallets set available_amount = available_amount + v_request.amount, reserved_amount = greatest(reserved_amount - v_request.amount, 0), updated_at = now() where id = v_wallet.id;
  update hq.ledger_operations set status = 'failed', metadata = metadata || jsonb_build_object('failure_reason', p_reason), updated_at = now() where reference_id = v_request.id::text and operation_type = 'EMPLOYEE_WITHDRAWAL' and status = 'processing';
  update hq.payout_requests set status = 'failed', failure_reason = p_reason, updated_at = now() where id = v_request.id;
  return jsonb_build_object('ok', true, 'status', 'failed', 'payout_request_id', v_request.id);
end;
$$;

revoke all on function public.hq_prepare_employee_paysuite_payout_v1(uuid,numeric,text,text,text) from public, anon, authenticated;
revoke all on function public.hq_complete_employee_paysuite_payout_v1(uuid,text) from public, anon, authenticated;
revoke all on function public.hq_fail_employee_paysuite_payout_v1(uuid,text) from public, anon, authenticated;
grant execute on function public.hq_prepare_employee_paysuite_payout_v1(uuid,numeric,text,text,text) to service_role;
grant execute on function public.hq_complete_employee_paysuite_payout_v1(uuid,text) to service_role;
grant execute on function public.hq_fail_employee_paysuite_payout_v1(uuid,text) to service_role;
notify pgrst, 'reload schema';
commit;
