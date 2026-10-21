-- Central HQ: credit confirmed DeliGo Eats and Mestre24 platform revenue
-- into CORPORATE_MZN, idempotently, and preserve dual-approval audit.

create table if not exists hq.corporate_revenue_credits (
  id uuid primary key default gen_random_uuid(),
  financial_event_id uuid not null unique references hq.platform_financial_events(id) on delete restrict,
  source_app text not null,
  source_record_id text,
  amount numeric(18,2) not null check (amount > 0),
  status text not null default 'credited' check (status in ('credited','reversed')),
  credit_operation_id uuid references hq.ledger_operations(id) on delete restrict,
  reversal_operation_id uuid references hq.ledger_operations(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists corporate_revenue_credits_source_idx
  on hq.corporate_revenue_credits(source_app, status);

alter table hq.corporate_revenue_credits enable row level security;
revoke all on hq.corporate_revenue_credits from public, anon, authenticated;
grant all on hq.corporate_revenue_credits to service_role;

create or replace function hq.sync_corporate_revenue_v1()
returns numeric
language plpgsql
security definer
set search_path = hq, public, pg_temp
as $$
declare
  v_wallet hq.logical_wallets%rowtype;
  v_event hq.platform_financial_events%rowtype;
  v_credit_id uuid;
  v_operation_id uuid;
  v_reversed hq.corporate_revenue_credits%rowtype;
begin
  select * into v_wallet
  from hq.logical_wallets
  where wallet_code = 'CORPORATE_MZN'
    and currency = 'MZN'
    and status = 'active'
  order by created_at
  limit 1
  for update;

  if v_wallet.id is null then
    raise exception 'corporate_wallet_not_found';
  end if;

  for v_event in
    select *
    from hq.platform_financial_events
    where source_app in ('deligo.orders', 'mestre24.subscriptions')
      and currency = 'MZN'
      and payment_status = 'confirmed'
      and coalesce(platform_fee, 0) > 0
    order by occurred_at, id
  loop
    v_credit_id := null;
    insert into hq.corporate_revenue_credits (
      financial_event_id, source_app, source_record_id, amount
    ) values (
      v_event.id, v_event.source_app, v_event.source_record_id,
      round(v_event.platform_fee, 2)
    )
    on conflict (financial_event_id) do nothing
    returning id into v_credit_id;

    if v_credit_id is not null then
      insert into hq.ledger_operations (
        wallet_from, wallet_to, amount, currency, operation_type,
        reference_id, status, requested_by, approved_by, executed_by,
        metadata, requested_at, approved_at, executed_at
      ) values (
        null, v_wallet.id, round(v_event.platform_fee, 2), 'MZN', 'REVENUE',
        'PLATFORM_FINANCIAL_EVENT:' || v_event.id::text, 'settled',
        null, null, null,
        jsonb_build_object(
          'purpose', 'corporate_platform_revenue',
          'source_app', v_event.source_app,
          'source_record_id', v_event.source_record_id,
          'financial_event_id', v_event.id
        ),
        now(), now(), now()
      ) returning id into v_operation_id;

      update hq.corporate_revenue_credits
      set credit_operation_id = v_operation_id, updated_at = now()
      where id = v_credit_id;

      update hq.logical_wallets
      set available_amount = available_amount + round(v_event.platform_fee, 2),
          updated_at = now()
      where id = v_wallet.id;
      v_wallet.available_amount := v_wallet.available_amount + round(v_event.platform_fee, 2);
    end if;
  end loop;

  for v_reversed in
    select c.*
    from hq.corporate_revenue_credits c
    join hq.platform_financial_events e on e.id = c.financial_event_id
    where c.status = 'credited'
      and (
        e.payment_status is distinct from 'confirmed'
        or e.currency is distinct from 'MZN'
        or coalesce(e.platform_fee, 0) <= 0
      )
    order by c.created_at, c.id
  loop
    if v_wallet.available_amount < v_reversed.amount then
      raise exception 'corporate_wallet_insufficient_for_reversal';
    end if;

    insert into hq.ledger_operations (
      wallet_from, wallet_to, amount, currency, operation_type,
      reference_id, status, metadata, requested_at, approved_at, executed_at
    ) values (
      v_wallet.id, null, v_reversed.amount, 'MZN', 'REVERSAL',
      'PLATFORM_FINANCIAL_EVENT:' || v_reversed.financial_event_id::text || ':REVERSAL',
      'settled',
      jsonb_build_object(
        'purpose', 'corporate_platform_revenue_reversal',
        'financial_event_id', v_reversed.financial_event_id
      ),
      now(), now(), now()
    ) returning id into v_operation_id;

    update hq.logical_wallets
    set available_amount = available_amount - v_reversed.amount,
        updated_at = now()
    where id = v_wallet.id;

    update hq.corporate_revenue_credits
    set status = 'reversed', reversal_operation_id = v_operation_id, updated_at = now()
    where id = v_reversed.id;

    v_wallet.available_amount := v_wallet.available_amount - v_reversed.amount;
  end loop;

  select available_amount into v_wallet.available_amount
  from hq.logical_wallets where id = v_wallet.id;
  return v_wallet.available_amount;
end;
$$;

revoke all on function hq.sync_corporate_revenue_v1() from public, anon, authenticated;
grant execute on function hq.sync_corporate_revenue_v1() to service_role;

create or replace function hq.corporate_revenue_summary_v1()
returns jsonb
language sql
stable
security definer
set search_path = hq, public, pg_temp
as $$
  select jsonb_build_object(
    'corporate_wallet_available', coalesce((
      select available_amount from hq.logical_wallets
      where wallet_code = 'CORPORATE_MZN' and currency = 'MZN' and status = 'active'
      order by created_at limit 1
    ), 0),
    'deligo_eats_confirmed', coalesce((
      select sum(amount) from hq.corporate_revenue_credits
      where source_app = 'deligo.orders' and status = 'credited'
    ), 0),
    'mestre24_confirmed', coalesce((
      select sum(amount) from hq.corporate_revenue_credits
      where source_app = 'mestre24.subscriptions' and status = 'credited'
    ), 0),
    'confirmed_event_count', (
      select count(*) from hq.corporate_revenue_credits where status = 'credited'
    )
  );
$$;

revoke all on function hq.corporate_revenue_summary_v1() from public, anon, authenticated;
grant execute on function hq.corporate_revenue_summary_v1() to service_role;

create or replace function hq.trg_sync_corporate_revenue_after_event()
returns trigger
language plpgsql
security definer
set search_path = hq, public, pg_temp
as $$
begin
  perform hq.sync_corporate_revenue_v1();
  return null;
end;
$$;

drop trigger if exists hq_sync_corporate_revenue_after_event on hq.platform_financial_events;
create trigger hq_sync_corporate_revenue_after_event
after insert or update of platform_fee, payment_status, currency
on hq.platform_financial_events
for each statement execute function hq.trg_sync_corporate_revenue_after_event();

select hq.sync_corporate_revenue_v1();

create or replace function public.hq_transfer_approved_profit_v1(p_withdrawal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, hq, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_withdrawal public.admin_corporate_withdrawals%rowtype;
  v_approval public.admin_corporate_withdrawal_approvals%rowtype;
  v_source hq.logical_wallets%rowtype;
  v_destination hq.logical_wallets%rowtype;
  v_requester_employee_id uuid;
  v_approver_employee_id uuid;
  v_amount numeric;
  v_operation uuid;
begin
  if v_actor is null then raise exception 'authentication_required'; end if;

  select * into v_withdrawal
  from public.admin_corporate_withdrawals
  where id = p_withdrawal_id
  for update;
  if v_withdrawal.id is null then raise exception 'withdrawal_not_found'; end if;
  if v_withdrawal.admin_id is distinct from v_actor then raise exception 'withdrawal_owner_required'; end if;
  if v_withdrawal.status = 'reserved' then
    return jsonb_build_object('ok', true, 'withdrawal_id', v_withdrawal.id, 'status', 'reserved');
  end if;
  if v_withdrawal.status <> 'approved' or v_withdrawal.approval_status <> 'approved' then
    raise exception 'second_approval_required';
  end if;

  select * into v_approval
  from public.admin_corporate_withdrawal_approvals
  where withdrawal_id = v_withdrawal.id and status = 'verified'
  order by verified_at desc
  limit 1
  for update;
  if v_approval.id is null then raise exception 'verified_second_approval_not_found'; end if;
  if v_withdrawal.second_approver_id is distinct from v_approval.approver_id then
    raise exception 'second_approver_mismatch';
  end if;

  select id into v_requester_employee_id
  from hq.employees
  where auth_user_id = v_withdrawal.admin_id and status = 'active'
  order by created_at limit 1;
  select id into v_approver_employee_id
  from hq.employees
  where auth_user_id = v_approval.approver_id and status = 'active'
  order by created_at limit 1;
  if v_requester_employee_id is null then raise exception 'requester_employee_not_found'; end if;
  if v_approver_employee_id is null then raise exception 'approver_employee_not_found'; end if;

  v_amount := round(v_withdrawal.amount, 2);
  select * into v_source
  from hq.logical_wallets
  where wallet_code = 'CORPORATE_MZN' and currency = 'MZN' and status = 'active'
  order by created_at limit 1 for update;
  if v_source.id is null then raise exception 'corporate_wallet_not_found'; end if;
  if v_source.available_amount < v_amount then raise exception 'corporate_wallet_insufficient'; end if;

  select * into v_destination
  from hq.logical_wallets
  where owner_user_id = v_actor and wallet_type = 'employee' and status = 'active' and currency = 'MZN'
  order by created_at limit 1 for update;
  if v_destination.id is null then raise exception 'employee_wallet_not_found'; end if;

  update hq.logical_wallets set available_amount = available_amount - v_amount, updated_at = now() where id = v_source.id;
  update hq.logical_wallets set available_amount = available_amount + v_amount, updated_at = now() where id = v_destination.id;

  insert into hq.ledger_operations (
    wallet_from, wallet_to, amount, currency, operation_type, reference_id, status,
    requested_by, approved_by, executed_by, second_approved_by, metadata, approved_at, executed_at
  ) values (
    v_source.id, v_destination.id, v_amount, 'MZN', 'INTERNAL_TRANSFER', v_withdrawal.id::text, 'settled',
    v_requester_employee_id, v_approver_employee_id, v_requester_employee_id, v_approver_employee_id,
    jsonb_build_object(
      'purpose', 'approved_corporate_profit_transfer',
      'withdrawal_id', v_withdrawal.id,
      'approval_id', v_approval.id,
      'second_approver_id', v_approval.approver_id
    ), now(), now()
  ) returning id into v_operation;

  update public.admin_corporate_withdrawals
  set status = 'reserved', updated_at = now()
  where id = v_withdrawal.id;
  update public.admin_corporate_withdrawal_approvals
  set status = 'consumed', consumed_at = now(), updated_at = now()
  where id = v_approval.id and status = 'verified';

  return jsonb_build_object(
    'ok', true,
    'withdrawal_id', v_withdrawal.id,
    'ledger_operation_id', v_operation,
    'amount', v_amount,
    'status', 'reserved',
    'requested_by', v_requester_employee_id,
    'approved_by', v_approver_employee_id
  );
end;
$$;

revoke all on function public.hq_transfer_approved_profit_v1(uuid) from public, anon;
grant execute on function public.hq_transfer_approved_profit_v1(uuid) to authenticated, service_role;
