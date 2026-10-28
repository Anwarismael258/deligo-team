-- PaySuite deposit settlement for the HQ corporate wallet.
-- The provider webhook remains the only authority that credits money.
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
set search_path = public, payments, hq, pg_temp
as $$
declare
  v_payment payments.payment_transactions%rowtype;
  v_wallet payments.wallet_accounts%rowtype;
  v_corporate hq.logical_wallets%rowtype;
  v_event_id uuid;
  v_entry_id uuid;
  v_operation_id uuid;
  v_is_corporate_deposit boolean := false;
  v_amount numeric(18,2);
  v_reference text;
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

  v_is_corporate_deposit := coalesce(v_payment.metadata->>'destination','') = 'hq_corporate_wallet';
  if p_event_type = 'payment.success' and p_status in ('settled','succeeded','success','paid') then
    if v_is_corporate_deposit then
      v_amount := round(p_amount_minor / 100.0, 2);
      v_reference := 'PAYSUITE-DEPOSIT:' || v_payment.id::text;
      select * into v_corporate from hq.logical_wallets
      where wallet_code = 'CORPORATE_MZN' and currency = 'MZN' and status = 'active'
      order by created_at limit 1 for update;
      if v_corporate.id is null then
        update payments.provider_webhook_events set payment_transaction_id=v_payment.id, processing_status='failed', error_code='corporate_wallet_not_found', processed_at=now() where id=v_event_id;
        return jsonb_build_object('ok',false,'reason','corporate_wallet_not_found');
      end if;
      if not exists (select 1 from hq.ledger_operations where reference_id=v_reference and status='settled') then
        update hq.logical_wallets
        set available_amount = available_amount + v_amount, updated_at = now()
        where id = v_corporate.id;
        insert into hq.ledger_operations (
          wallet_from, wallet_to, amount, currency, operation_type, reference_id, status,
          requested_by, approved_by, executed_by, metadata, requested_at, approved_at, executed_at
        ) values (
          null, v_corporate.id, v_amount, 'MZN', 'ADJUSTMENT', v_reference, 'settled',
          null, null, null,
          jsonb_build_object('purpose','paysuite_corporate_deposit','payment_transaction_id',v_payment.id,'provider_reference',p_provider_reference,'actor_employee_id',v_payment.metadata->>'actor_employee_id'),
          now(), now(), now()
        ) returning id into v_operation_id;
      end if;
    else
      select * into v_wallet from payments.wallet_accounts where id=v_payment.wallet_account_id for update;
      if not found then
        update payments.provider_webhook_events set payment_transaction_id=v_payment.id, processing_status='failed', error_code='wallet_not_found', processed_at=now() where id=v_event_id;
        return jsonb_build_object('ok',false,'reason','wallet_not_found');
      end if;
      insert into payments.wallet_ledger_entries
        (wallet_account_id, app_id, payment_transaction_id, entry_side, entry_type, currency_code, amount_minor, balance_after_minor, reference_type, reference_id, description, metadata)
      values (v_wallet.id, v_payment.app_id, v_payment.id, 'credit', 'deposit', v_wallet.currency_code, p_amount_minor,
        coalesce(v_wallet.available_balance_minor,0)+p_amount_minor, 'payment_transaction', v_payment.id::text,
        'Depósito PaySuite confirmado', jsonb_build_object('provider','paysuite','event_type',p_event_type,'provider_reference',p_provider_reference))
      on conflict (payment_transaction_id, entry_type) where payment_transaction_id is not null and entry_type='deposit'
      do nothing returning id into v_entry_id;
      if v_entry_id is not null then
        update payments.wallet_accounts set available_balance_minor=coalesce(available_balance_minor,0)+p_amount_minor, updated_at=now() where id=v_wallet.id;
      end if;
    end if;
  end if;

  update payments.payment_transactions set status=case when p_event_type='payment.failed' then 'failed' else 'settled' end,
    provider_reference=coalesce(nullif(trim(p_provider_reference),''),provider_reference),
    settled_at=case when p_event_type='payment.success' then coalesce(settled_at,now()) else settled_at end,
    failed_at=case when p_event_type='payment.failed' then coalesce(failed_at,now()) else failed_at end, updated_at=now()
  where id=v_payment.id and status in ('pending','processing');
  update payments.provider_webhook_events set payment_transaction_id=v_payment.id, processing_status='processed', processed_at=now() where id=v_event_id;
  return jsonb_build_object('ok',true,'duplicate',false,'payment_transaction_id',v_payment.id,'ledger_entry_id',v_entry_id,'hq_operation_id',v_operation_id,'status',p_status,'destination',case when v_is_corporate_deposit then 'hq_corporate_wallet' else 'wallet' end);
end;
$$;

revoke all on function public.process_paysuite_webhook_v1(text,text,text,bigint,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.process_paysuite_webhook_v1(text,text,text,bigint,text,text,jsonb) to service_role;
notify pgrst, 'reload schema';
commit;
