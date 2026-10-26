begin;

-- Keep the Central on the same Mozambique operator mapping used by the DeliGo
-- applications. The phone is the source of truth; the browser never selects
-- a payout operator and no provider secret is stored in the database.
alter table if exists hq.payout_requests drop constraint if exists payout_requests_provider_check;
alter table if exists hq.payout_requests
  add constraint payout_requests_provider_check
  check (provider is null or provider in ('vodacom_mpesa','movitel','tmcel_mkesh'));

alter table if exists hq.payout_provider_events drop constraint if exists payout_provider_events_provider_check;
alter table if exists hq.payout_provider_events
  add constraint payout_provider_events_provider_check
  check (provider in ('vodacom_mpesa','movitel','tmcel_mkesh'));

alter table if exists hq.payment_accounts drop constraint if exists payment_accounts_provider_check;
alter table if exists hq.payment_accounts
  add constraint payment_accounts_provider_check
  check (provider in ('vodacom_mpesa','movitel','tmcel_mkesh','bank','other'));

alter table if exists hq.employee_display_profiles drop constraint if exists employee_display_profiles_wallet_provider_check;
alter table if exists hq.employee_display_profiles
  add constraint employee_display_profiles_wallet_provider_check
  check (wallet_provider is null or wallet_provider in ('vodacom_mpesa','movitel','tmcel_mkesh'));

alter table if exists hq.employee_wallet_change_requests drop constraint if exists employee_wallet_change_requests_provider_check;
alter table if exists hq.employee_wallet_change_requests
  add constraint employee_wallet_change_requests_provider_check
  check (provider in ('vodacom_mpesa','movitel','tmcel_mkesh'));

alter table if exists hq.employee_wallet_change_history drop constraint if exists employee_wallet_change_history_provider_check;
alter table if exists hq.employee_wallet_change_history
  add constraint employee_wallet_change_history_provider_check
  check (provider in ('vodacom_mpesa','movitel','tmcel_mkesh'));

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
  v_phone text := regexp_replace(coalesce(p_phone_number, ''), '[^0-9]', '', 'g');
  v_local text := case when left(v_phone, 3) = '258' then substring(v_phone from 4) else v_phone end;
  v_method text := lower(coalesce(nullif(trim(p_method), ''), ''));
  v_provider text;
  v_reference text := 'DLG-HQ-PAYOUT-' || replace(gen_random_uuid()::text, '-', '');
begin
  if p_actor_auth_user_id is null then raise exception 'authentication_required'; end if;
  if v_amount <= 0 then raise exception 'invalid_payout_amount'; end if;
  if nullif(btrim(coalesce(p_idempotency_key, '')), '') is null then raise exception 'payout_idempotency_required'; end if;
  if length(v_local) = 10 and left(v_local, 1) = '0' then v_local := substring(v_local from 2); end if;
  if v_local !~ '^8[2-7][0-9]{7}$' then raise exception 'invalid_paysuite_phone'; end if;
  -- 82/83 Tmcel/mKesh, 84/85 Vodacom/M-Pesa, 86/87 Movitel/e-Mola.
  if left(v_local, 2) in ('82', '83') then
    if v_method <> 'mkesh' then raise exception 'paysuite_operator_mismatch'; end if;
    v_provider := 'tmcel_mkesh';
  elsif left(v_local, 2) in ('84', '85') then
    if v_method <> 'mpesa' then raise exception 'paysuite_operator_mismatch'; end if;
    v_provider := 'vodacom_mpesa';
  else
    if v_method <> 'emola' then raise exception 'paysuite_operator_mismatch'; end if;
    v_provider := 'movitel';
  end if;

  select * into v_request from hq.payout_requests where idempotency_key = btrim(p_idempotency_key) limit 1;
  if v_request.id is not null then
    return jsonb_build_object('ok', true, 'payout_request_id', v_request.id, 'reference', v_request.metadata->>'reference', 'status', v_request.status, 'amount', v_request.amount, 'idempotent', true, 'provider', v_request.provider);
  end if;
  select * into v_employee from hq.employees where auth_user_id = p_actor_auth_user_id and status = 'active' order by created_at limit 1;
  if v_employee.id is null then raise exception 'employee_not_found'; end if;
  select * into v_wallet from hq.logical_wallets where owner_user_id = p_actor_auth_user_id and wallet_type = 'employee' and status = 'active' and currency = 'MZN' order by created_at limit 1 for update;
  if v_wallet.id is null then raise exception 'employee_wallet_not_found'; end if;
  if coalesce(v_wallet.available_amount, 0) < v_amount then raise exception 'employee_wallet_insufficient'; end if;

  insert into hq.payout_requests (request_type, beneficiary_user_id, beneficiary_reference, amount, currency, provider, destination_number, status, idempotency_key, source_reference, metadata, requested_by)
  values ('withdrawal', p_actor_auth_user_id, p_phone_number, v_amount, 'MZN', v_provider, p_phone_number, 'processing', btrim(p_idempotency_key), v_wallet.wallet_code,
    jsonb_build_object('reference', v_reference, 'source', 'hq_employee_wallet', 'method', v_method, 'operator', v_provider), v_employee.id)
  returning * into v_request;

  update hq.logical_wallets set available_amount = available_amount - v_amount, reserved_amount = reserved_amount + v_amount, updated_at = now() where id = v_wallet.id;
  insert into hq.ledger_operations (wallet_from, amount, currency, operation_type, reference_id, status, requested_by, provider, metadata)
  values (v_wallet.id, v_amount, 'MZN', 'EMPLOYEE_WITHDRAWAL', v_request.id::text, 'processing', v_employee.id, v_provider,
    jsonb_build_object('reference', v_reference, 'payout_request_id', v_request.id, 'destination', p_phone_number, 'method', v_method));
  return jsonb_build_object('ok', true, 'payout_request_id', v_request.id, 'reference', v_reference, 'status', 'processing', 'amount', v_amount, 'provider', v_provider, 'method', v_method);
end;
$$;

revoke all on function public.hq_prepare_employee_paysuite_payout_v1(uuid,numeric,text,text,text) from public, anon, authenticated;
grant execute on function public.hq_prepare_employee_paysuite_payout_v1(uuid,numeric,text,text,text) to service_role;
notify pgrst, 'reload schema';
commit;
