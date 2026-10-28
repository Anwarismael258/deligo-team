begin;
-- Repeated browser requests claim one durable attempt before reserving money.
create table if not exists hq.employee_withdrawal_intents(
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references hq.employees(id),
 client_id uuid not null,amount_minor bigint not null check(amount_minor>0),method text not null check(method in ('mpesa','emola')),
 response jsonb,http_status integer not null default 202,created_at timestamptz not null default now(),unique(employee_id,client_id)
);
alter table hq.employee_withdrawal_intents enable row level security;
revoke all on hq.employee_withdrawal_intents from public,anon,authenticated;
grant all on hq.employee_withdrawal_intents to service_role;
create or replace function hq.claim_employee_withdrawal_v1(p_employee uuid,p_client uuid,p_minor bigint,p_method text) returns jsonb
language plpgsql security definer set search_path=hq,public as $$
declare r employee_withdrawal_intents; fresh boolean;
begin
 if not exists(select 1 from employees where id=p_employee and status='active') then raise exception 'Sem acesso activo';end if;
 insert into employee_withdrawal_intents(employee_id,client_id,amount_minor,method) values(p_employee,p_client,p_minor,p_method) on conflict do nothing returning * into r;
 fresh:=found;
 if not fresh then select * into r from employee_withdrawal_intents where employee_id=p_employee and client_id=p_client;end if;
 if r.amount_minor<>p_minor or r.method<>p_method then raise exception 'Pedido repetido com dados diferentes';end if;
 return jsonb_build_object('id',r.id,'fresh',fresh,'response',r.response,'http_status',r.http_status);
end $$;
revoke all on function hq.claim_employee_withdrawal_v1(uuid,uuid,bigint,text) from public,anon,authenticated;
grant execute on function hq.claim_employee_withdrawal_v1(uuid,uuid,bigint,text) to service_role;
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
  v_reference text := 'DLGHQ' || left(replace(gen_random_uuid()::text, '-', ''),24);
begin
  if p_actor_auth_user_id is null then raise exception 'authentication_required'; end if;
  if v_amount <= 0 then raise exception 'invalid_payout_amount'; end if;
  if nullif(btrim(coalesce(p_idempotency_key, '')), '') is null then raise exception 'payout_idempotency_required'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_auth_user_id::text,0));
  select * into v_request from hq.payout_requests where idempotency_key = btrim(p_idempotency_key) limit 1;
  if v_request.id is not null then
    if v_request.beneficiary_user_id<>p_actor_auth_user_id or v_request.amount<>v_amount then raise exception 'payout_idempotency_mismatch';end if;
    return jsonb_build_object('ok', true, 'payout_request_id', v_request.id, 'reference', v_request.metadata->>'reference', 'status', v_request.status, 'amount', v_request.amount, 'idempotent', true);
  end if;

  select * into v_employee from hq.employees where auth_user_id = p_actor_auth_user_id and status = 'active' order by created_at limit 1;
  if v_employee.id is null then raise exception 'employee_not_found'; end if;
  select * into v_wallet from hq.logical_wallets where owner_user_id = p_actor_auth_user_id and wallet_type = 'employee' and status = 'active' and currency = 'MZN' and available_amount>=v_amount order by created_at limit 1 for update;
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
  if v_request.status<>'processing' then raise exception 'payout_not_processing';end if;
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
  if v_request.status in ('paid','failed', 'reversed', 'cancelled') then return jsonb_build_object('ok', true, 'status', v_request.status, 'idempotent', true); end if;
  if v_request.status<>'processing' then raise exception 'payout_not_processing';end if;
  select * into v_wallet from hq.logical_wallets where wallet_code = v_request.source_reference and status = 'active' for update;
  if v_wallet.id is null then raise exception 'employee_wallet_not_found'; end if;
  if coalesce(v_wallet.reserved_amount,0)<v_request.amount then raise exception 'payout_reservation_missing';end if;
  update hq.logical_wallets set available_amount = available_amount + v_request.amount, reserved_amount = greatest(reserved_amount - v_request.amount, 0), updated_at = now() where id = v_wallet.id;
  update hq.ledger_operations set status = 'failed', metadata = metadata || jsonb_build_object('failure_reason', p_reason), updated_at = now() where reference_id = v_request.id::text and operation_type = 'EMPLOYEE_WITHDRAWAL' and status = 'processing';
  update hq.payout_requests set status = 'failed', failure_reason = p_reason, updated_at = now() where id = v_request.id;
  return jsonb_build_object('ok', true, 'status', 'failed', 'payout_request_id', v_request.id);
end;
$$;

create or replace function public.reserve_paysuite_payout_v1(p_payout_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public,payments as $$
declare r payments.payout_requests%rowtype; w payments.wallet_accounts%rowtype;
begin
 select * into r from payments.payout_requests where id=p_payout_request_id for update;
 if not found then raise exception 'payout_not_found'; end if;
 if r.status='processing' then return jsonb_build_object('ok',true,'idempotent',true);end if;
 if r.status not in ('pending','approved') then raise exception 'payout_not_pending';end if;
 select * into w from payments.wallet_accounts where id=r.source_wallet_account_id for update;
 if not found or coalesce(r.amount_minor,0)<=0 then raise exception 'payout_wallet_invalid'; end if;
 if coalesce(w.available_balance_minor,0) < r.amount_minor then raise exception 'insufficient_available_balance'; end if;
 update payments.wallet_accounts set available_balance_minor=available_balance_minor-r.amount_minor, reserved_balance_minor=reserved_balance_minor+r.amount_minor, updated_at=now() where id=w.id;
 update payments.payout_requests set status='processing', reviewed_at=coalesce(reviewed_at,now()), updated_at=now() where id=r.id and status in ('pending','approved','processing');
 return jsonb_build_object('ok',true,'payout_request_id',r.id,'reserved_minor',r.amount_minor);
end; $$;

create or replace function public.complete_paysuite_payout_v1(p_payout_request_id uuid,p_provider_reference text)
returns jsonb language plpgsql security definer set search_path=public,payments as $$
declare
  r payments.payout_requests%rowtype;
  w payments.wallet_accounts%rowtype;
  e uuid;
  v_fee_minor bigint;
  v_net_minor bigint;
begin
  select * into r from payments.payout_requests where id=p_payout_request_id for update;
  if r.id is null then raise exception 'payout_not_found';end if;
  if r.status='paid' then return jsonb_build_object('ok',true,'idempotent',true);end if;
  if r.status<>'processing' then raise exception 'payout_not_processing';end if;
  select * into w from payments.wallet_accounts where id=r.source_wallet_account_id for update;
  if not found or coalesce(w.reserved_balance_minor,0)<r.amount_minor then raise exception 'payout_reservation_missing'; end if;
  v_fee_minor := greatest(least(coalesce(r.fee_minor, round(r.amount_minor * 0.03)::bigint), r.amount_minor - 1), 0);
  v_net_minor := r.amount_minor - v_fee_minor;
  insert into payments.wallet_ledger_entries(wallet_account_id,app_id,entry_side,entry_type,currency_code,amount_minor,balance_after_minor,reference_type,reference_id,description,metadata)
  values(w.id,w.app_id,'debit','withdrawal',w.currency_code,r.amount_minor,coalesce(w.available_balance_minor,0),'payout_request',r.id::text,'Levantamento PaySuite concluído (3% de taxa)',jsonb_build_object(
    'provider','paysuite','provider_reference',p_provider_reference,'gross_amount_minor',r.amount_minor,'provider_fee_minor',v_fee_minor,'net_amount_minor',v_net_minor
  )) returning id into e;
  update payments.wallet_accounts set reserved_balance_minor=reserved_balance_minor-r.amount_minor, updated_at=now() where id=w.id;
  update payments.payout_requests set fee_minor=v_fee_minor, provider_reference=p_provider_reference, status='paid', paid_at=coalesce(paid_at,now()), metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object('gross_amount_minor',r.amount_minor,'provider_fee_minor',v_fee_minor,'net_amount_minor',v_net_minor), updated_at=now() where id=r.id;
  return jsonb_build_object('ok',true,'ledger_entry_id',e,'gross_amount_minor',r.amount_minor,'provider_fee_minor',v_fee_minor,'net_amount_minor',v_net_minor);
end; $$;

create or replace function public.fail_paysuite_payout_v1(p_payout_request_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,payments as $$
declare r payments.payout_requests%rowtype; w payments.wallet_accounts%rowtype;
begin
 select * into r from payments.payout_requests where id=p_payout_request_id for update;
 if r.id is null then raise exception 'payout_not_found';end if;
 if r.status in ('paid','failed','cancelled','reversed') then return jsonb_build_object('ok',true,'status',r.status,'idempotent',true);end if;
 if r.status<>'processing' then raise exception 'payout_not_processing';end if;
 select * into w from payments.wallet_accounts where id=r.source_wallet_account_id for update;
 if not found or coalesce(w.reserved_balance_minor,0)<r.amount_minor then raise exception 'payout_reservation_missing'; end if;
 update payments.wallet_accounts set reserved_balance_minor=reserved_balance_minor-r.amount_minor, available_balance_minor=available_balance_minor+r.amount_minor, updated_at=now() where id=w.id;
 update payments.payout_requests set status='failed', rejection_reason=p_reason, updated_at=now() where id=r.id;
 return jsonb_build_object('ok',true,'released_minor',r.amount_minor);
end; $$;
revoke all on function public.hq_prepare_employee_paysuite_payout_v1(uuid,numeric,text,text,text),public.hq_complete_employee_paysuite_payout_v1(uuid,text),public.hq_fail_employee_paysuite_payout_v1(uuid,text),public.reserve_paysuite_payout_v1(uuid),public.complete_paysuite_payout_v1(uuid,text),public.fail_paysuite_payout_v1(uuid,text) from public,anon,authenticated;
grant execute on function public.hq_prepare_employee_paysuite_payout_v1(uuid,numeric,text,text,text),public.hq_complete_employee_paysuite_payout_v1(uuid,text),public.hq_fail_employee_paysuite_payout_v1(uuid,text),public.reserve_paysuite_payout_v1(uuid),public.complete_paysuite_payout_v1(uuid,text),public.fail_paysuite_payout_v1(uuid,text) to service_role;
notify pgrst,'reload schema';
commit;
