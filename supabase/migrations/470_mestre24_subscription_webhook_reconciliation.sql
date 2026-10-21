-- Reconcile Mestre24 subscription callbacks in the shared PaySuite webhook.
-- The provider sends the callback to the Central Supabase project, while the
-- generic wallet processor only knows payments.payment_transactions. Keep the
-- existing wallet path and handle subscription_cycles before that lookup.

create or replace function public.process_paysuite_webhook_v1(
  p_signature text,
  p_event_type text,
  p_external_reference text,
  p_amount_minor bigint,
  p_provider_reference text,
  p_status text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, payments, mestre24, hq, pg_temp
as $function$
declare
  v_payment payments.payment_transactions%rowtype;
  v_wallet payments.wallet_accounts%rowtype;
  v_cycle mestre24.subscription_cycles%rowtype;
  v_owner_user_id uuid;
  v_event_id uuid;
  v_entry_id uuid;
  v_hq_event_id uuid;
  v_starts_at timestamptz;
  v_expires_at timestamptz;
begin
  if nullif(trim(p_signature), '') is null
     or nullif(trim(p_external_reference), '') is null
     or p_amount_minor is null
     or p_amount_minor <= 0 then
    raise exception 'invalid_paysuite_webhook_arguments';
  end if;

  begin
    insert into payments.provider_webhook_events(
      provider, signature, provider_event_type, external_reference, payload
    ) values (
      'paysuite', p_signature, nullif(trim(p_event_type), ''),
      trim(p_external_reference), coalesce(p_payload, '{}'::jsonb)
    ) returning id into v_event_id;
  exception when unique_violation then
    return jsonb_build_object('ok', true, 'duplicate', true);
  end;

  -- A Mestre24 subscription is a confirmed corporate-revenue event, not a
  -- wallet deposit. The reference is the cycle's provider_reference.
  select * into v_cycle
  from mestre24.subscription_cycles
  where provider_reference = trim(p_external_reference)
  for update;

  if found then
    if round(v_cycle.amount * 100)::bigint <> p_amount_minor then
      update payments.provider_webhook_events
      set processing_status = 'failed', error_code = 'amount_mismatch', processed_at = now()
      where id = v_event_id;
      return jsonb_build_object('ok', false, 'reason', 'amount_mismatch', 'cycle_id', v_cycle.id);
    end if;

    if p_event_type = 'payment.success' then
      v_starts_at := coalesce(v_cycle.paid_at, now());
      v_expires_at := v_starts_at + interval '30 days';

      update mestre24.subscription_cycles
      set status = 'active', starts_at = v_starts_at, expires_at = v_expires_at, paid_at = v_starts_at
      where id = v_cycle.id;

      update mestre24.professional_profiles
      set subscription_status = 'active', subscription_expires_at = v_expires_at, updated_at = v_starts_at
      where user_id = v_cycle.professional_user_id;

      select public.hq_ingest_platform_financial_event_v1(
        p_platform_slug => 'mestre24',
        p_source_app => 'mestre24.subscriptions',
        p_transaction_type => 'professional_subscription',
        p_gross_amount => v_cycle.amount,
        p_payment_status => 'confirmed',
        p_source_record_id => 'mestre24:subscription:' || v_cycle.id::text,
        p_entity_type => 'subscription_cycle',
        p_entity_id => v_cycle.id::text,
        p_user_id => v_cycle.professional_user_id,
        p_platform_fee => v_cycle.amount,
        p_provider_fee => 0,
        p_partner_amount => 0,
        p_currency => v_cycle.currency,
        p_payment_method => v_cycle.provider,
        p_reference => trim(p_external_reference),
        p_metadata => coalesce(p_payload, '{}'::jsonb),
        p_occurred_at => v_starts_at
      ) into v_hq_event_id;

      update payments.provider_webhook_events
      set processing_status = 'processed', error_code = null, processed_at = now()
      where id = v_event_id;
      return jsonb_build_object(
        'ok', true,
        'subscription', 'active',
        'cycle_id', v_cycle.id,
        'hq_event_id', v_hq_event_id,
        'expires_at', v_expires_at
      );
    end if;

    if p_event_type = 'payment.failed' then
      update mestre24.subscription_cycles
      set status = 'failed'
      where id = v_cycle.id and status in ('pending', 'paid');

      select public.hq_ingest_platform_financial_event_v1(
        p_platform_slug => 'mestre24',
        p_source_app => 'mestre24.subscriptions',
        p_transaction_type => 'professional_subscription',
        p_gross_amount => v_cycle.amount,
        p_payment_status => 'failed',
        p_source_record_id => 'mestre24:subscription:' || v_cycle.id::text,
        p_entity_type => 'subscription_cycle',
        p_entity_id => v_cycle.id::text,
        p_user_id => v_cycle.professional_user_id,
        p_platform_fee => 0,
        p_provider_fee => 0,
        p_partner_amount => 0,
        p_currency => v_cycle.currency,
        p_payment_method => v_cycle.provider,
        p_reference => trim(p_external_reference),
        p_metadata => coalesce(p_payload, '{}'::jsonb),
        p_occurred_at => now()
      ) into v_hq_event_id;

      update payments.provider_webhook_events
      set processing_status = 'processed', error_code = null, processed_at = now()
      where id = v_event_id;
      return jsonb_build_object('ok', true, 'subscription', 'failed', 'cycle_id', v_cycle.id);
    end if;

    update payments.provider_webhook_events
    set processing_status = 'received', processed_at = null
    where id = v_event_id;
    return jsonb_build_object('ok', true, 'subscription', 'processing', 'cycle_id', v_cycle.id);
  end if;

  -- Existing DeliGo wallet-deposit path.
  select * into v_payment
  from payments.payment_transactions
  where provider = 'paysuite' and external_reference = trim(p_external_reference)
  for update;
  if not found then
    update payments.provider_webhook_events
    set processing_status = 'ignored', error_code = 'payment_not_found', processed_at = now()
    where id = v_event_id;
    return jsonb_build_object('ok', true, 'ignored', true, 'reason', 'payment_not_found');
  end if;

  if v_payment.amount_minor <> p_amount_minor then
    update payments.provider_webhook_events
    set payment_transaction_id = v_payment.id, processing_status = 'failed',
        error_code = 'amount_mismatch', processed_at = now()
    where id = v_event_id;
    return jsonb_build_object('ok', false, 'reason', 'amount_mismatch');
  end if;

  if p_event_type = 'payment.success'
     and p_status in ('settled', 'succeeded', 'success', 'paid') then
    select owner_user_id into v_owner_user_id
    from payments.wallet_accounts where id = v_payment.wallet_account_id;
    if v_owner_user_id is not null then
      perform pg_advisory_xact_lock(hashtextextended('deligo:account-financial:' || v_owner_user_id::text, 0));
    end if;

    select * into v_wallet from payments.wallet_accounts
    where id = v_payment.wallet_account_id for update;
    if not found then
      update payments.provider_webhook_events
      set payment_transaction_id = v_payment.id, processing_status = 'failed',
          error_code = 'wallet_not_found', processed_at = now()
      where id = v_event_id;
      return jsonb_build_object('ok', false, 'reason', 'wallet_not_found');
    end if;

    insert into payments.wallet_ledger_entries(
      wallet_account_id, app_id, payment_transaction_id, entry_side, entry_type,
      currency_code, amount_minor, balance_after_minor, reference_type, reference_id,
      description, metadata
    ) values (
      v_wallet.id, v_payment.app_id, v_payment.id, 'credit', 'deposit',
      v_wallet.currency_code, p_amount_minor,
      coalesce(v_wallet.available_balance_minor, 0) + p_amount_minor,
      'payment_transaction', v_payment.id::text, 'Deposito PaySuite confirmado',
      jsonb_build_object('provider', 'paysuite', 'event_type', p_event_type, 'provider_reference', p_provider_reference)
    ) on conflict(payment_transaction_id, entry_type)
      where payment_transaction_id is not null and entry_type = 'deposit'
      do nothing returning id into v_entry_id;

    if v_entry_id is not null then
      update payments.wallet_accounts
      set available_balance_minor = coalesce(available_balance_minor, 0) + p_amount_minor,
          updated_at = now()
      where id = v_wallet.id;
    end if;
  end if;

  update payments.payment_transactions
  set status = case when p_event_type = 'payment.failed' then 'failed' else 'settled' end,
      provider_reference = coalesce(nullif(trim(p_provider_reference), ''), provider_reference),
      settled_at = case when p_event_type = 'payment.success' then coalesce(settled_at, now()) else settled_at end,
      failed_at = case when p_event_type = 'payment.failed' then coalesce(failed_at, now()) else failed_at end,
      updated_at = now()
  where id = v_payment.id and status in ('pending', 'processing');

  update payments.provider_webhook_events
  set payment_transaction_id = v_payment.id, processing_status = 'processed', processed_at = now()
  where id = v_event_id;
  return jsonb_build_object('ok', true, 'duplicate', false, 'payment_transaction_id', v_payment.id, 'ledger_entry_id', v_entry_id, 'status', p_status);
end;
$function$;

revoke all on function public.process_paysuite_webhook_v1(text,text,text,bigint,text,text,jsonb) from public, anon;
grant execute on function public.process_paysuite_webhook_v1(text,text,text,bigint,text,text,jsonb) to service_role;
