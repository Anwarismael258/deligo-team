create or replace function hq.claim_employee_paysuite_dispatch_v1(p_kind text,p_payout_id uuid,p_owner uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare e hq.employees; c payments.payout_requests; h hq.payout_requests; meta jsonb; gross bigint; fee bigint; phone text; method text; reference text; fresh boolean; wid uuid;
begin
 select * into e from hq.employees where auth_user_id=p_owner and status='active' order by created_at limit 1;
 if e.id is null then raise exception 'employee_not_active'; end if;
 if p_kind='canonical' then
  select * into c from payments.payout_requests where id=p_payout_id for update;
  if not found or c.beneficiary_user_id is distinct from p_owner then raise exception 'payout_owner_required'; end if;
  if c.metadata->>'unified_withdrawal' is distinct from 'true' or c.metadata->>'employee_id' is distinct from e.id::text then raise exception 'central_payout_required'; end if;
  if c.status not in ('processing','paid') then raise exception 'payout_not_reserved'; end if;
  if c.status='processing' and not exists(select 1 from payments.wallet_accounts w where w.id=c.source_wallet_account_id and w.owner_user_id=p_owner and w.reserved_balance_minor>=c.amount_minor) then raise exception 'payout_reservation_missing'; end if;
  meta:=coalesce(c.metadata,'{}'::jsonb);gross:=c.amount_minor;fee:=c.fee_minor;phone:=c.destination_phone;method:=c.method;
 elsif p_kind='hq' then
  select * into h from hq.payout_requests where id=p_payout_id for update;
  if not found or h.beneficiary_user_id is distinct from p_owner then raise exception 'payout_owner_required'; end if;
  if h.metadata->>'source' is distinct from 'hq_employee_wallet' or h.requested_by is distinct from e.id then raise exception 'central_payout_required'; end if;
  if h.status not in ('processing','paid','completed') then raise exception 'payout_not_reserved'; end if;
  if h.status='processing' and not exists(select 1 from hq.logical_wallets w where w.wallet_code=h.source_reference and w.owner_user_id=p_owner and w.reserved_amount>=h.amount) then raise exception 'payout_reservation_missing'; end if;
  meta:=coalesce(h.metadata,'{}'::jsonb);gross:=round(h.amount*100);fee:=round(gross*0.03);phone:=h.destination_number;method:=meta->>'method';
 else raise exception 'payout_kind_invalid'; end if;
 if gross<=0 or fee<>round(gross*0.03) or gross-fee<100 then raise exception 'payout_amount_invalid'; end if;
 phone:=regexp_replace(coalesce(phone,''),'[^0-9]','','g');
 if left(phone,3)='258' then phone:=substr(phone,4);end if;
 if phone!~'^8[2-7][0-9]{7}$' or (left(phone,2) in ('84','85') and method<>'mpesa') or (left(phone,2) in ('86','87') and method<>'emola') or (left(phone,2) in ('82','83') and method<>'mkesh') then raise exception 'payout_operator_invalid'; end if;
 reference:=meta->>'reference';
 if reference is null or reference!~'^[A-Za-z0-9]{1,30}$' then raise exception 'payout_reference_invalid';end if;
 fresh:=not(meta?'central_dispatch_started_at');
 if fresh then
  meta:=meta||jsonb_build_object('central_dispatch_started_at',now());
  if p_kind='canonical' then update payments.payout_requests set metadata=meta,updated_at=now() where id=p_payout_id;
  else update hq.payout_requests set metadata=meta,updated_at=now() where id=p_payout_id;end if;
 end if;
 return jsonb_build_object('fresh',fresh,'kind',p_kind,'id',p_payout_id,'owner',p_owner,'gross_minor',gross,'fee_minor',fee,'net_minor',gross-fee,'phone',phone,'method',method,'reference',reference,'holder',e.display_name,'metadata',meta);
end $$;
revoke all on function hq.claim_employee_paysuite_dispatch_v1(text,uuid,uuid) from public,anon,authenticated;
grant execute on function hq.claim_employee_paysuite_dispatch_v1(text,uuid,uuid) to service_role;
notify pgrst,'reload schema';
