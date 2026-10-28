begin;
create or replace function public.settle_confirmed_paysuite_deposit_v1(p_reference text,p_amount numeric,p_provider_id text,p_payload jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare d public.wallet_deposits%rowtype; fee numeric; net numeric; e uuid;
begin
 select * into d from public.wallet_deposits where reference=p_reference for update;
 if d.id is null then raise exception 'deposit_not_found'; end if;
 if round(p_amount,2)<>round(d.amount,2) or p_amount<=0 or coalesce(p_provider_id,'')='' then raise exception 'deposit_provider_mismatch'; end if;
 fee:=round(d.amount*0.03,2);net:=d.amount-fee;
 perform public.apply_wallet_ledger_entry(p_wallet_id=>d.wallet_id,p_user_id=>d.user_id,p_direction=>'credit',p_entry_type=>'deposit_net',p_amount=>net,p_reference_key=>'deposit-net-'||d.id::text,p_metadata=>jsonb_build_object('deposit_id',d.id,'gross_amount',d.amount,'gateway_fee',fee,'provider','paysuite'),p_status=>'confirmed',p_allow_negative=>false);
 update public.wallet_deposits set status='completed',gateway_fee=fee,net_amount=net,transaction_id=p_provider_id,provider_status='completed',provider_payload=p_payload,processed_at=coalesce(processed_at,now()),updated_at=now() where id=d.id;
 select employee_id into e from hq.personal_deposit_checkouts where deposit_id=d.id;
 if e is not null then perform hq.sync_personal_checkout_deposits_v1(e); end if;
 return jsonb_build_object('ok',true,'deposit_id',d.id,'net_amount',net);
end $$;
revoke all on function public.settle_confirmed_paysuite_deposit_v1(text,numeric,text,jsonb) from public,anon,authenticated;
grant execute on function public.settle_confirmed_paysuite_deposit_v1(text,numeric,text,jsonb) to service_role;
notify pgrst,'reload schema';
commit;
