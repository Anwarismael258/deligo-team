begin;

-- CasaDireta is already provisioned in the shared TUPC database. Register the
-- app in the Central catalogue so it is visible in the platform selector and
-- receives the same authorization/status treatment as the other products.
alter table core.apps drop constraint if exists core_apps_module_schema_check;
alter table core.apps add constraint core_apps_module_schema_check
  check (module_schema in ('deligo', 'comunhao', 'sarca', 'taomoz', 'mestre24', 'exploremoz', 'casadireta'));

insert into core.apps (
  slug, name, display_name, description, runtime_type, module_schema, is_active, is_public
) values (
  'casadireta', 'CasaDireta', 'CasaDireta',
  'Arrendamento, imóveis, perfis de proprietário e inquilino.',
  'web', 'casadireta', true, true
)
on conflict (slug) do update set
  name = excluded.name,
  display_name = excluded.display_name,
  description = excluded.description,
  runtime_type = excluded.runtime_type,
  module_schema = excluded.module_schema,
  is_active = true,
  is_public = true,
  updated_at = now();

insert into hq.platforms (
  legal_entity_id, slug, name, schema_name, status, platform_code, icon_key,
  integration_status, base_url
)
select
  le.id, 'casadireta', 'CasaDireta', 'casadireta', 'active', 'CASADIRETA',
  'casadireta', 'connected', null
from hq.legal_entities le
where le.legal_name = 'DeliGo Triunfal, Lda.'
limit 1
on conflict (slug) do update set
  name = excluded.name,
  schema_name = excluded.schema_name,
  status = excluded.status,
  platform_code = excluded.platform_code,
  icon_key = excluded.icon_key,
  integration_status = excluded.integration_status,
  updated_at = now();

insert into casadireta.subscription_plans (
  code, name, price_minor, currency_code, billing_cycle_days, metadata
) values (
  'casadireta_monthly_99_mzn', 'CasaDireta mensal', 9900, 'MZN', 30,
  jsonb_build_object(
    'app_code', 'casadireta',
    'amount_major', 99,
    'revenue_owner', 'central',
    'provider', 'paysuite',
    'provider_fee_rate', 0.03,
    'provider_fee_minor', 297,
    'net_corporate_amount_minor', 9603
  )
)
on conflict (code) do update set
  name = excluded.name,
  price_minor = excluded.price_minor,
  currency_code = excluded.currency_code,
  billing_cycle_days = excluded.billing_cycle_days,
  metadata = excluded.metadata,
  is_active = true,
  updated_at = now();

-- PaySuite receives 3% of the gross subscription amount. For 99 MZN:
-- gross 99.00, provider fee 2.97, Central net revenue 96.03.
create or replace function casadireta.settle_subscription_payment(
  p_reference text,
  p_amount_minor bigint,
  p_provider text,
  p_provider_reference text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = casadireta, payments, core, hq, public
as $function$
declare
  v_cycle casadireta.subscription_cycles%rowtype;
  v_app_id uuid;
  v_payment_id uuid;
  v_idempotency_id uuid;
  v_event_group_id uuid;
  v_platform_wallet_id uuid;
  v_clearing_wallet_id uuid;
  v_provider_fee_wallet_id uuid;
  v_platform_balance bigint;
  v_clearing_balance bigint;
  v_provider_fee_balance bigint;
  v_provider_fee_minor bigint;
  v_net_amount_minor bigint;
  v_hq_event_id uuid;
begin
  if p_reference is null or p_reference !~ '^SUB_CD_[0-9a-f-]+_[0-9a-f-]+$' then
    raise exception 'invalid_casadireta_reference';
  end if;
  if p_amount_minor is null or p_amount_minor <> 9900 then
    raise exception 'subscription_amount_mismatch';
  end if;

  v_provider_fee_minor := round(p_amount_minor * 0.03)::bigint;
  v_net_amount_minor := p_amount_minor - v_provider_fee_minor;
  if v_net_amount_minor <= 0 then
    raise exception 'subscription_net_amount_not_positive';
  end if;

  select * into v_cycle
  from casadireta.subscription_cycles
  where provider_reference = p_reference
  for update;
  if not found then raise exception 'subscription_reference_not_found'; end if;
  if v_cycle.amount_minor <> p_amount_minor then raise exception 'subscription_cycle_amount_mismatch'; end if;
  if v_cycle.status in ('paid', 'active') and v_cycle.payment_transaction_id is not null then
    return jsonb_build_object('ok', true, 'idempotent_replay', true,
      'subscription_id', v_cycle.id, 'payment_transaction_id', v_cycle.payment_transaction_id,
      'gross_amount_minor', p_amount_minor, 'provider_fee_minor', v_provider_fee_minor,
      'net_amount_minor', v_net_amount_minor);
  end if;

  select id into v_app_id from core.apps where slug = 'casadireta';
  if v_app_id is null then raise exception 'casadireta_app_not_registered'; end if;

  insert into payments.idempotency_keys (
    id, app_id, scope_name, idempotency_key, request_hash, request_payload,
    status, created_by, locked_at, finalized_at
  ) values (
    gen_random_uuid(), v_app_id, 'casadireta.subscription.settlement',
    'settle:' || p_reference, md5(p_reference || ':' || p_amount_minor::text),
    jsonb_build_object('reference', p_reference, 'amount_minor', p_amount_minor,
      'provider', p_provider, 'provider_reference', p_provider_reference,
      'provider_fee_minor', v_provider_fee_minor),
    'in_progress', v_cycle.user_id, now(), null
  ) on conflict (scope_name, idempotency_key) do nothing
  returning id into v_idempotency_id;

  if v_idempotency_id is null then
    select id, status into v_idempotency_id, v_cycle.status
    from payments.idempotency_keys
    where scope_name = 'casadireta.subscription.settlement'
      and idempotency_key = 'settle:' || p_reference;
    if v_cycle.status = 'completed' then
      return jsonb_build_object('ok', true, 'idempotent_replay', true, 'subscription_id', v_cycle.id);
    end if;
  end if;

  insert into payments.wallet_accounts (app_id, account_code, account_type, currency_code, metadata)
  values (v_app_id, 'casadireta:platform:MZN', 'platform', 'MZN',
    '{"app_code":"casadireta","revenue_owner":"central"}'::jsonb)
  on conflict (account_code) do update set app_id = excluded.app_id, updated_at = now()
  returning id into v_platform_wallet_id;
  if v_platform_wallet_id is null then
    select id into v_platform_wallet_id from payments.wallet_accounts where account_code = 'casadireta:platform:MZN';
  end if;

  insert into payments.wallet_accounts (app_id, account_code, account_type, currency_code, metadata)
  values (v_app_id, 'casadireta:mobile_money_clearing:MZN', 'system', 'MZN',
    '{"app_code":"casadireta","purpose":"external_provider_clearing"}'::jsonb)
  on conflict (account_code) do update set app_id = excluded.app_id, updated_at = now()
  returning id into v_clearing_wallet_id;
  if v_clearing_wallet_id is null then
    select id into v_clearing_wallet_id from payments.wallet_accounts where account_code = 'casadireta:mobile_money_clearing:MZN';
  end if;

  insert into payments.wallet_accounts (app_id, account_code, account_type, currency_code, metadata)
  values (v_app_id, 'casadireta:paysuite_fee:MZN', 'system', 'MZN',
    '{"app_code":"casadireta","purpose":"paysuite_provider_fee","provider_fee_rate":0.03}'::jsonb)
  on conflict (account_code) do update set app_id = excluded.app_id, updated_at = now()
  returning id into v_provider_fee_wallet_id;
  if v_provider_fee_wallet_id is null then
    select id into v_provider_fee_wallet_id from payments.wallet_accounts where account_code = 'casadireta:paysuite_fee:MZN';
  end if;

  select available_balance_minor into v_platform_balance from payments.wallet_accounts where id = v_platform_wallet_id for update;
  select available_balance_minor into v_clearing_balance from payments.wallet_accounts where id = v_clearing_wallet_id for update;
  select available_balance_minor into v_provider_fee_balance from payments.wallet_accounts where id = v_provider_fee_wallet_id for update;

  insert into payments.payment_transactions (
    app_id, initiator_user_id, wallet_account_id, idempotency_key_id,
    transaction_type, status, funds_status, amount_minor, fee_minor,
    provider, provider_reference, external_reference, metadata, settled_at,
    reference, method, platform_slug
  ) values (
    v_app_id, v_cycle.user_id, v_platform_wallet_id, v_idempotency_id,
    'topup', 'settled', 'released', p_amount_minor, v_provider_fee_minor,
    p_provider, p_provider_reference, p_reference,
    jsonb_build_object('app_code','casadireta','revenue_owner','central',
      'gross_amount_minor',p_amount_minor,'provider_fee_minor',v_provider_fee_minor,
      'net_amount_minor',v_net_amount_minor,'payload',coalesce(p_payload, '{}'::jsonb)),
    now(), p_reference, v_cycle.operator, 'casadireta'
  ) returning id into v_payment_id;

  insert into payments.financial_event_groups (
    app_id, idempotency_key_id, event_code, currency_code, reference_type,
    reference_id, status, expected_debits_minor, expected_credits_minor, metadata, posted_at
  ) values (
    v_app_id, v_idempotency_id, 'casadireta_subscription_settlement', 'MZN',
    'casadireta.subscription_cycle', v_cycle.id::text, 'posted', p_amount_minor, p_amount_minor,
    jsonb_build_object('reference', p_reference, 'provider', p_provider,
      'provider_fee_minor', v_provider_fee_minor), now()
  ) returning id into v_event_group_id;

  update payments.wallet_accounts set available_balance_minor = available_balance_minor + v_net_amount_minor, updated_at = now() where id = v_platform_wallet_id;
  update payments.wallet_accounts set available_balance_minor = available_balance_minor - p_amount_minor, updated_at = now() where id = v_clearing_wallet_id;
  update payments.wallet_accounts set available_balance_minor = available_balance_minor + v_provider_fee_minor, updated_at = now() where id = v_provider_fee_wallet_id;

  insert into payments.wallet_ledger_entries (
    wallet_account_id, app_id, event_group_id, idempotency_key_id, payment_transaction_id,
    counterparty_wallet_account_id, entry_side, entry_type, currency_code, amount_minor,
    balance_after_minor, reference_type, reference_id, description, metadata
  ) values
  (v_clearing_wallet_id, v_app_id, v_event_group_id, v_idempotency_id, v_payment_id,
    v_platform_wallet_id, 'debit', 'external_subscription_clearing', 'MZN', p_amount_minor,
    v_clearing_balance - p_amount_minor, 'casadireta.subscription', v_cycle.id::text,
    'CasaDireta PaySuite clearing', jsonb_build_object('reference', p_reference)),
  (v_platform_wallet_id, v_app_id, v_event_group_id, v_idempotency_id, v_payment_id,
    v_clearing_wallet_id, 'credit', 'casadireta_subscription_revenue', 'MZN', v_net_amount_minor,
    v_platform_balance + v_net_amount_minor, 'casadireta.subscription', v_cycle.id::text,
    'CasaDireta subscription revenue to Central', jsonb_build_object('reference', p_reference, 'provider_fee_minor', v_provider_fee_minor)),
  (v_provider_fee_wallet_id, v_app_id, v_event_group_id, v_idempotency_id, v_payment_id,
    v_clearing_wallet_id, 'credit', 'paysuite_provider_fee', 'MZN', v_provider_fee_minor,
    v_provider_fee_balance + v_provider_fee_minor, 'casadireta.subscription', v_cycle.id::text,
    'PaySuite provider fee (3%)', jsonb_build_object('reference', p_reference, 'gross_amount_minor', p_amount_minor));

  select public.hq_ingest_platform_financial_event_v1(
    p_platform_slug => 'casadireta',
    p_source_app => 'casadireta.subscriptions',
    p_transaction_type => 'subscription',
    p_gross_amount => p_amount_minor / 100.0,
    p_payment_status => 'confirmed',
    p_source_record_id => 'casadireta:subscription:' || v_cycle.id::text,
    p_entity_type => 'subscription_cycle',
    p_entity_id => v_cycle.id::text,
    p_user_id => v_cycle.user_id,
    p_platform_fee => v_net_amount_minor / 100.0,
    p_provider_fee => v_provider_fee_minor / 100.0,
    p_partner_amount => 0,
    p_currency => v_cycle.currency_code,
    p_payment_method => v_cycle.operator,
    p_reference => p_reference,
    p_metadata => coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('provider_fee_rate', 0.03),
    p_occurred_at => now()
  ) into v_hq_event_id;

  update casadireta.subscription_cycles
  set status = 'active', provider_payment_id = p_provider_reference,
      payment_transaction_id = v_payment_id, paid_at = now(),
      period_started_at = now(), period_ends_at = now() + interval '30 days', updated_at = now()
  where id = v_cycle.id;
  update payments.idempotency_keys set status = 'completed', finalized_at = now(), updated_at = now() where id = v_idempotency_id;

  return jsonb_build_object('ok', true, 'subscription_id', v_cycle.id,
    'payment_transaction_id', v_payment_id, 'hq_event_id', v_hq_event_id,
    'gross_amount_minor', p_amount_minor, 'provider_fee_minor', v_provider_fee_minor,
    'net_amount_minor', v_net_amount_minor);
exception when others then
  if v_idempotency_id is not null then
    update payments.idempotency_keys set status = 'failed', finalized_at = now(), updated_at = now()
    where id = v_idempotency_id and status = 'in_progress';
  end if;
  raise;
end;
$function$;

revoke all on function casadireta.settle_subscription_payment(text, bigint, text, text, jsonb) from public, anon, authenticated;
grant execute on function casadireta.settle_subscription_payment(text, bigint, text, text, jsonb) to service_role;

commit;
