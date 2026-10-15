-- Payout reservation lifecycle. No provider call and no wallet reset.
begin;
alter table if exists payments.wallet_accounts
  add column if not exists reserved_balance_minor bigint not null default 0
  check (reserved_balance_minor >= 0);

create or replace function public.reserve_paysuite_payout_v1(p_payout_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public,payments as $$
declare r payments.payout_requests%rowtype; w payments.wallet_accounts%rowtype;
begin
 select * into r from payments.payout_requests where id=p_payout_request_id for update;
 if not found then raise exception 'payout_not_found'; end if;
 select * into w from payments.wallet_accounts where id=r.source_wallet_account_id for update;
 if not found or coalesce(r.amount_minor,0)<=0 then raise exception 'payout_wallet_invalid'; end if;
 if coalesce(w.available_balance_minor,0) < r.amount_minor then raise exception 'insufficient_available_balance'; end if;
 update payments.wallet_accounts set available_balance_minor=available_balance_minor-r.amount_minor, reserved_balance_minor=reserved_balance_minor+r.amount_minor, updated_at=now() where id=w.id;
 update payments.payout_requests set status='processing', reviewed_at=coalesce(reviewed_at,now()), updated_at=now() where id=r.id and status in ('pending','approved','processing');
 return jsonb_build_object('ok',true,'payout_request_id',r.id,'reserved_minor',r.amount_minor);
end; $$;

create or replace function public.complete_paysuite_payout_v1(p_payout_request_id uuid,p_provider_reference text)
returns jsonb language plpgsql security definer set search_path=public,payments as $$
declare r payments.payout_requests%rowtype; w payments.wallet_accounts%rowtype; e uuid;
begin
 select * into r from payments.payout_requests where id=p_payout_request_id for update;
 select * into w from payments.wallet_accounts where id=r.source_wallet_account_id for update;
 if not found or coalesce(w.reserved_balance_minor,0)<r.amount_minor then raise exception 'payout_reservation_missing'; end if;
 insert into payments.wallet_ledger_entries(wallet_account_id,app_id,entry_side,entry_type,currency_code,amount_minor,balance_after_minor,reference_type,reference_id,description,metadata)
 values(w.id,w.app_id,'debit','withdrawal',w.currency_code,r.amount_minor,coalesce(w.available_balance_minor,0),'payout_request',r.id::text,'Levantamento PaySuite concluído',jsonb_build_object('provider','paysuite','provider_reference',p_provider_reference)) returning id into e;
 update payments.wallet_accounts set reserved_balance_minor=reserved_balance_minor-r.amount_minor, updated_at=now() where id=w.id;
 update payments.payout_requests set status='paid', provider_reference=p_provider_reference, paid_at=coalesce(paid_at,now()), updated_at=now() where id=r.id;
 return jsonb_build_object('ok',true,'ledger_entry_id',e);
end; $$;

create or replace function public.fail_paysuite_payout_v1(p_payout_request_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,payments as $$
declare r payments.payout_requests%rowtype; w payments.wallet_accounts%rowtype;
begin
 select * into r from payments.payout_requests where id=p_payout_request_id for update;
 select * into w from payments.wallet_accounts where id=r.source_wallet_account_id for update;
 if not found or coalesce(w.reserved_balance_minor,0)<r.amount_minor then raise exception 'payout_reservation_missing'; end if;
 update payments.wallet_accounts set reserved_balance_minor=reserved_balance_minor-r.amount_minor, available_balance_minor=available_balance_minor+r.amount_minor, updated_at=now() where id=w.id;
 update payments.payout_requests set status='failed', rejection_reason=p_reason, updated_at=now() where id=r.id;
 return jsonb_build_object('ok',true,'released_minor',r.amount_minor);
end; $$;
revoke all on function public.reserve_paysuite_payout_v1(uuid),public.complete_paysuite_payout_v1(uuid,text),public.fail_paysuite_payout_v1(uuid,text) from public;
grant execute on function public.reserve_paysuite_payout_v1(uuid),public.complete_paysuite_payout_v1(uuid,text),public.fail_paysuite_payout_v1(uuid,text) to service_role;
commit;
