begin;
create table if not exists hq.personal_deposit_checkouts(
 deposit_id uuid primary key references public.wallet_deposits(id),
 employee_id uuid not null references hq.employees(id),
 created_at timestamptz not null default now(),synced_at timestamptz
);
alter table hq.personal_deposit_checkouts enable row level security;
revoke all on hq.personal_deposit_checkouts from public,anon,authenticated;
grant select,insert,update on hq.personal_deposit_checkouts to service_role;
create index if not exists personal_deposit_employee_pending on hq.personal_deposit_checkouts(employee_id) where synced_at is null;
create or replace function hq.sync_personal_checkout_deposits_v1(p_employee_id uuid) returns integer
language plpgsql security invoker set search_path='' as $$
declare receipt record; credited public.wallet_ledger%rowtype; wallet payments.wallet_accounts%rowtype; owner_id uuid; net_minor bigint; total integer:=0; ref text;
begin
 select auth_user_id into owner_id from hq.employees where id=p_employee_id and status='active';
 if owner_id is null then raise exception 'active_employee_required'; end if;
 for receipt in select c.deposit_id,d.wallet_id,d.user_id,d.amount,d.net_amount from hq.personal_deposit_checkouts c join public.wallet_deposits d on d.id=c.deposit_id where c.employee_id=p_employee_id and c.synced_at is null and d.status='completed' order by c.created_at for update of c loop
  -- A signed webhook's confirmed ledger credit is required, not a return URL.
  select * into credited from public.wallet_ledger where wallet_id=receipt.wallet_id and reference_key='deposit-net-'||receipt.deposit_id::text and direction='credit' and status='confirmed' and entry_type='deposit_net';
  if credited.id is null then continue; end if;
  net_minor:=round(credited.amount*100)::bigint;
  if net_minor<=0 or net_minor<>round((receipt.amount-round(receipt.amount*0.03,2))*100)::bigint then raise exception 'deposit_net_mismatch'; end if;
  ref:='hq-personal-deposit:'||receipt.deposit_id::text;
  select * into wallet from payments.wallet_accounts where owner_user_id=owner_id and app_id is null and account_type='user' and currency_code='MZN' and status='active' order by created_at limit 1 for update;
  if wallet.id is null then
   insert into payments.wallet_accounts(owner_user_id,app_id,account_code,account_type,currency_code,available_balance_minor,pending_balance_minor,reserved_balance_minor,status,metadata) values(owner_id,null,'HQ-LEGACY-'||owner_id::text,'user','MZN',0,0,0,'active','{"provider_integration":"paysuite","withdrawal_disabled":false}'::jsonb) returning * into wallet;
  end if;
  -- Debit exactly this new deposit. Existing balances are left in place.
  perform public.apply_wallet_ledger_entry(p_wallet_id=>receipt.wallet_id,p_user_id=>receipt.user_id,p_direction=>'debit',p_entry_type=>'hq_deposit_consolidation',p_amount=>credited.amount,p_reference_key=>ref,p_metadata=>jsonb_build_object('deposit_id',receipt.deposit_id,'destination_wallet_id',wallet.id),p_status=>'confirmed',p_allow_negative=>false);
  update payments.wallet_accounts set available_balance_minor=available_balance_minor+net_minor,updated_at=now() where id=wallet.id;
  insert into payments.wallet_ledger_entries(wallet_account_id,entry_side,entry_type,currency_code,amount_minor,balance_after_minor,reference_type,reference_id,description,metadata)
  select wallet.id,'credit','deposit','MZN',net_minor,available_balance_minor,'hq_personal_deposit',receipt.deposit_id::text,'Depósito pessoal PaySuite (líquido de 3%)',jsonb_build_object('source_wallet_id',receipt.wallet_id,'deposit_id',receipt.deposit_id,'gross_amount',receipt.amount,'fee_rate',0.03) from payments.wallet_accounts where id=wallet.id;
  update hq.personal_deposit_checkouts set synced_at=now() where deposit_id=receipt.deposit_id;
  total:=total+1;
 end loop;
 return total;
end $$;
revoke all on function hq.sync_personal_checkout_deposits_v1(uuid) from public,anon,authenticated;
grant execute on function hq.sync_personal_checkout_deposits_v1(uuid) to service_role;
notify pgrst,'reload schema';
commit;
