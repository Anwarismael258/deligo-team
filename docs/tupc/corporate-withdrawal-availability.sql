begin;
create or replace function hq.corporate_revenue_availability_v1() returns jsonb
language plpgsql security invoker set search_path='' as $$
declare revenue numeric:=0; sent numeric:=0; committed numeric:=0; cash numeric:=0; wid uuid;
begin
 select id,available_amount into wid,cash from hq.logical_wallets where wallet_code='CORPORATE_MZN' and currency='MZN' and status='active' order by created_at limit 1;
 if wid is null then raise exception 'corporate_wallet_not_found'; end if;
 select coalesce(sum(e.platform_fee),0) into revenue from hq.platform_financial_events e join hq.platforms p on p.id=e.platform_id
 where p.slug in ('deligo','mestre24','sarca','comunhao','taomoz') and e.currency='MZN' and e.payment_status='confirmed'
 and e.metadata->>'test_mode' is distinct from 'true' and e.metadata->>'fictitious' is distinct from 'true' and coalesce(e.source_record_id,'') not like 'TEST-%';
 select coalesce(sum(amount),0) into sent from hq.ledger_operations where wallet_from=wid and status='settled' and operation_type in ('INTERNAL_TRANSFER','WITHDRAWAL','PAYOUT');
 select coalesce(sum(w.amount),0) into committed from public.admin_corporate_withdrawals w
 where (w.status in ('approved','reserved','processing','paid') or (w.status='pending_approval' and exists(select 1 from public.admin_corporate_withdrawal_approvals a where a.withdrawal_id=w.id and a.status='pending' and a.otp_expires_at>now())))
 and not exists(select 1 from hq.ledger_operations o where o.wallet_from=wid and o.reference_id=w.id::text and o.status='settled');
 return jsonb_build_object('corporate_revenue_confirmed',round(revenue,2),'corporate_revenue_transferred',round(sent,2),'corporate_pending_withdrawals',round(committed,2),'corporate_wallet_available',round(cash,2),'corporate_profit_withdrawable',round(greatest(least(cash,revenue-sent)-committed,0),2),'source','hq.platform_financial_events + corporate settled transfers and live approvals');
end $$;
revoke all on function hq.corporate_revenue_availability_v1() from public,anon,authenticated;
grant execute on function hq.corporate_revenue_availability_v1() to service_role;
alter table public.admin_corporate_withdrawals drop constraint admin_corporate_withdrawals_method_check;
alter table public.admin_corporate_withdrawals add constraint admin_corporate_withdrawals_method_check check(method in ('mpesa','emola','internal_transfer'));
CREATE OR REPLACE FUNCTION public.hq_prepare_corporate_withdrawal_v1(p_amount numeric, p_method text, p_phone_number text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'hq', 'pg_temp'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_actor_role text;
  v_available numeric;
  v_approver uuid;
  v_fee numeric;
  v_net numeric;
  v_existing public.admin_corporate_withdrawals%rowtype;
  v_row public.admin_corporate_withdrawals%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication_required';
  end if;

  select r.code
    into v_actor_role
  from hq.employees e
  join hq.roles r on r.id = e.primary_role_id
  where e.auth_user_id = v_actor
    and e.status = 'active';

  if v_actor_role is null or v_actor_role not in ('SUPER_ADMIN', 'FINANCE') then
    raise exception 'dual_approval_role_required';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount';
  end if;

  if p_method not in ('mpesa', 'emola', 'internal_transfer') then
    raise exception 'invalid_method';
  end if;

  if length(trim(coalesce(p_phone_number, ''))) < 9 then
    raise exception 'invalid_phone';
  end if;

  if length(trim(coalesce(p_idempotency_key, ''))) < 8 then
    raise exception 'invalid_idempotency_key';
  end if;

  select *
    into v_existing
  from public.admin_corporate_withdrawals
  where idempotency_key = p_idempotency_key;

  if v_existing.id is not null then
    if v_existing.admin_id is distinct from v_actor then raise exception 'withdrawal_owner_required'; end if;
    return jsonb_build_object(
      'success', true,
      'idempotent', true,
      'withdrawal_id', v_existing.id,
      'status', v_existing.status,
      'approval_status', v_existing.approval_status
    );
  end if;

  perform 1 from hq.logical_wallets where wallet_code='CORPORATE_MZN' and currency='MZN' and status='active' order by created_at limit 1 for update;
  v_available:=(hq.corporate_revenue_availability_v1()->>'corporate_profit_withdrawable')::numeric;
  if round(p_amount,2)>v_available then raise exception 'corporate_revenue_insufficient: % MZN',v_available; end if;

  select e.auth_user_id
    into v_approver
  from hq.employees e
  join hq.roles r on r.id = e.primary_role_id
  where e.status = 'active'
    and (
      (v_actor_role = 'SUPER_ADMIN' and r.code = 'FINANCE')
      or
      (v_actor_role = 'FINANCE' and r.code = 'SUPER_ADMIN')
    )
    and e.auth_user_id <> v_actor
  limit 1;

  if v_approver is null then
    raise exception 'second_approver_not_available';
  end if;

  v_fee := case when p_method='internal_transfer' then 0 else round((p_amount * 0.03)::numeric, 2) end;
  v_net := round((p_amount - v_fee)::numeric, 2);

  insert into public.admin_corporate_withdrawals (
    admin_id,
    amount,
    fee_amount,
    net_amount,
    method,
    phone_number,
    status,
    approval_status,
    requester_role,
    second_approver_id,
    idempotency_key
  )
  values (
    v_actor,
    round(p_amount, 2),
    v_fee,
    v_net,
    p_method,
    trim(p_phone_number),
    'pending_approval',
    'pending_second_approval',
    v_actor_role,
    v_approver,
    p_idempotency_key
  )
  returning * into v_row;

  insert into public.admin_corporate_withdrawal_approvals (
    withdrawal_id,
    requester_id,
    requester_role,
    approver_id,
    approver_role,
    otp_challenge_id,
    otp_expires_at
  )
  values (
    v_row.id,
    v_actor,
    v_actor_role,
    v_approver,
    case when v_actor_role = 'SUPER_ADMIN'
      then 'FINANCE' else 'SUPER_ADMIN' end,
    'pending-' || v_row.id::text,
    now() + interval '10 minutes'
  );

  return jsonb_build_object(
    'success', true,
    'withdrawal_id', v_row.id,
    'status', v_row.status,
    'approval_status', v_row.approval_status,
    'approver_id', v_approver,
    'otp_required', true
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.hq_transfer_approved_profit_v1(p_withdrawal_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'hq', 'pg_temp'
AS $function$
declare v_actor uuid:=auth.uid(); w public.admin_corporate_withdrawals%rowtype; a public.admin_corporate_withdrawal_approvals%rowtype; s hq.logical_wallets%rowtype; d hq.logical_wallets%rowtype; req uuid; appr uuid; amt numeric; op uuid;
begin
if v_actor is null then raise exception 'authentication_required'; end if;
select * into w from public.admin_corporate_withdrawals where id=p_withdrawal_id for update;
if w.id is null then raise exception 'withdrawal_not_found'; end if;
if w.admin_id is distinct from v_actor then raise exception 'withdrawal_owner_required'; end if;
if w.status='reserved' then return jsonb_build_object('ok',true,'withdrawal_id',w.id,'status','reserved'); end if;
if w.status<>'approved' or w.approval_status<>'approved' then raise exception 'second_approval_required'; end if;
select * into a from public.admin_corporate_withdrawal_approvals where withdrawal_id=w.id and status='verified' order by verified_at desc limit 1 for update;
if a.id is null then raise exception 'verified_second_approval_not_found'; end if;
if w.second_approver_id is distinct from a.approver_id then raise exception 'second_approver_mismatch'; end if;
select id into req from hq.employees where auth_user_id=w.admin_id and status='active' order by created_at limit 1;
select id into appr from hq.employees where auth_user_id=a.approver_id and status='active' order by created_at limit 1;
if req is null then raise exception 'requester_employee_not_found'; end if;
if appr is null then raise exception 'approver_employee_not_found'; end if;
amt=round(w.amount,2);
select * into s from hq.logical_wallets where wallet_code='CORPORATE_MZN' and currency='MZN' and status='active' order by created_at limit 1 for update;
if s.id is null then raise exception 'corporate_wallet_not_found'; end if;
if s.available_amount<amt then raise exception 'corporate_wallet_insufficient'; end if;
select * into d from hq.logical_wallets where owner_user_id=w.admin_id and wallet_type='employee' and status='active' and currency='MZN' order by created_at limit 1 for update;
if d.id is null then raise exception 'employee_wallet_not_found'; end if;
update hq.logical_wallets set available_amount=available_amount-amt,updated_at=now() where id=s.id;
update hq.logical_wallets set available_amount=available_amount+amt,updated_at=now() where id=d.id;
insert into hq.ledger_operations(wallet_from,wallet_to,amount,currency,operation_type,reference_id,status,requested_by,approved_by,executed_by,second_approved_by,metadata,approved_at,executed_at) values(s.id,d.id,amt,'MZN','INTERNAL_TRANSFER',w.id::text,'settled',req,appr,req,appr,jsonb_build_object('purpose','approved_corporate_profit_to_requesting_admin','withdrawal_id',w.id,'approval_id',a.id,'second_approver_id',a.approver_id),now(),now()) returning id into op;
update public.admin_corporate_withdrawals set status='reserved',updated_at=now() where id=w.id;
update public.admin_corporate_withdrawal_approvals set status='consumed',consumed_at=now(),updated_at=now() where id=a.id and status='verified';
return jsonb_build_object('ok',true,'withdrawal_id',w.id,'ledger_operation_id',op,'amount',amt,'status','reserved','requested_by',req,'approved_by',appr,'destination_user_id',w.admin_id);
end;$function$;

notify pgrst,'reload schema';
commit;

