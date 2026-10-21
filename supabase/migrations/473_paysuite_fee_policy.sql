-- PaySuite fee policy: all generic payins and payouts use the provider's 3% fee.
-- Keep gross, provider fee and net values explicit; never credit a wallet with
-- a provider charge that was not received.
begin;

create or replace function public.process_paysuite_webhook_v1(
  p_signature text,
  p_event_type text,
  p_external_reference text,
  p_amount_minor bigint,
  p_provider_reference text,
  p_status text,
  p_payload jsonb
) returns jsonb
language plpgsql security definer
set search_path = public, payments
as $$
declare
  v_payment payments.payment_transactions%rowtype;
  v_wallet payments.wallet_accounts%rowtype;
  v_event_id uuid;
  v_entry_id uuid;
  v_provider_fee_minor bigint;
  v_net_amount_minor bigint;
begin
  if nullif(trim(p_signature),'') is null or nullif(trim(p_external_reference),'') is null
     or p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_paysuite_webhook_arguments';
  end if;

  begin
    insert into payments.provider_webhook_events
      (provider, signature, provider_event_type, external_reference, payload)
    values ('paysuite', p_signature, nullif(trim(p_event_type),''), trim(p_external_reference), coalesce(p_payload,'{}'::jsonb))
    returning id into v_event_id;
  exception when unique_violation then
    return jsonb_build_object('ok',true,'duplicate',true);
  end;

  select * into v_payment from payments.payment_transactions
  where provider='paysuite' and external_reference=trim(p_external_reference)
  for update;
  if not found then
    update payments.provider_webhook_events set processing_status='ignored', error_code='payment_not_found', processed_at=now() where id=v_event_id;
    return jsonb_build_object('ok',true,'ignored',true,'reason','payment_not_found');
  end if;
  if v_payment.amount_minor <> p_amount_minor then
    update payments.provider_webhook_events set payment_transaction_id=v_payment.id, processing_status='failed', error_code='amount_mismatch', processed_at=now() where id=v_event_id;
    return jsonb_build_object('ok',false,'reason','amount_mismatch');
  end if;

  v_provider_fee_minor := case
    when p_event_type = 'payment.success' and p_status in ('settled','succeeded','success','paid')
      then round(p_amount_minor * 0.03)::bigint
    else 0
  end;
  v_net_amount_minor := p_amount_minor - v_provider_fee_minor;
  if v_net_amount_minor <= 0 then
    raise exception 'paysuite_net_amount_not_positive';
  end if;

  if p_event_type = 'payment.success' and p_status in ('settled','succeeded','success','paid') then
    select * into v_wallet from payments.wallet_accounts where id=v_payment.wallet_account_id for update;
    if not found then
      update payments.provider_webhook_events set payment_transaction_id=v_payment.id, processing_status='failed', error_code='wallet_not_found', processed_at=now() where id=v_event_id;
      return jsonb_build_object('ok',false,'reason','wallet_not_found');
    end if;
    insert into payments.wallet_ledger_entries
      (wallet_account_id, app_id, payment_transaction_id, entry_side, entry_type, currency_code, amount_minor, balance_after_minor, reference_type, reference_id, description, metadata)
    values (v_wallet.id, v_payment.app_id, v_payment.id, 'credit', 'deposit', v_wallet.currency_code, v_net_amount_minor,
      coalesce(v_wallet.available_balance_minor,0)+v_net_amount_minor, 'payment_transaction', v_payment.id::text,
      'Depósito PaySuite líquido (3% de taxa)', jsonb_build_object(
        'provider','paysuite', 'event_type',p_event_type, 'provider_reference',p_provider_reference,
        'gross_amount_minor',p_amount_minor, 'provider_fee_minor',v_provider_fee_minor, 'net_amount_minor',v_net_amount_minor
      ))
    on conflict (payment_transaction_id, entry_type) where payment_transaction_id is not null and entry_type='deposit' do nothing
    returning id into v_entry_id;
    if v_entry_id is not null then
      update payments.wallet_accounts set available_balance_minor=coalesce(available_balance_minor,0)+v_net_amount_minor, updated_at=now() where id=v_wallet.id;
    end if;
  end if;

  update payments.payment_transactions set status=case when p_event_type='payment.failed' then 'failed' else 'settled' end,
    fee_minor=v_provider_fee_minor,
    provider_reference=coalesce(nullif(trim(p_provider_reference),''),provider_reference),
    metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'gross_amount_minor',p_amount_minor, 'provider_fee_minor',v_provider_fee_minor, 'net_amount_minor',v_net_amount_minor
    ),
    settled_at=case when p_event_type='payment.success' then coalesce(settled_at,now()) else settled_at end,
    failed_at=case when p_event_type='payment.failed' then coalesce(failed_at,now()) else failed_at end, updated_at=now()
  where id=v_payment.id and status in ('pending','processing');
  update payments.provider_webhook_events set payment_transaction_id=v_payment.id, processing_status='processed', processed_at=now() where id=v_event_id;
  return jsonb_build_object('ok',true,'duplicate',false,'payment_transaction_id',v_payment.id,'ledger_entry_id',v_entry_id,
    'gross_amount_minor',p_amount_minor,'provider_fee_minor',v_provider_fee_minor,'net_amount_minor',v_net_amount_minor,'status',p_status);
end;
$$;

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

revoke all on function public.process_paysuite_webhook_v1(text,text,text,bigint,text,text,jsonb) from public;
grant execute on function public.process_paysuite_webhook_v1(text,text,text,bigint,text,text,jsonb) to service_role;
revoke all on function public.complete_paysuite_payout_v1(uuid,text) from public;
grant execute on function public.complete_paysuite_payout_v1(uuid,text) to service_role;
commit;
