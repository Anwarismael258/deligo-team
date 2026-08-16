begin;

create or replace function public.hq_ensure_test_wallet_v1(
  p_owner_user_id uuid,
  p_app_id uuid,
  p_account_code text,
  p_account_type text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = payments, public, pg_temp
as $$
declare
  v_wallet_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'HQ_TEST_WALLET_SERVICE_ROLE_REQUIRED';
  end if;

  insert into payments.wallet_accounts (
    owner_user_id, app_id, account_code, account_type, currency_code,
    available_balance_minor, pending_balance_minor, status, metadata
  ) values (
    p_owner_user_id, p_app_id, p_account_code, p_account_type, 'MZN',
    0, 0, 'active', coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object('test_mode', true)
  )
  on conflict (account_code) do update set
    available_balance_minor = 0,
    pending_balance_minor = 0,
    status = 'active',
    metadata = payments.wallet_accounts.metadata || excluded.metadata,
    updated_at = now()
  returning id into v_wallet_id;

  return v_wallet_id;
end;
$$;

revoke all on function public.hq_ensure_test_wallet_v1(uuid, uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.hq_ensure_test_wallet_v1(uuid, uuid, text, text, jsonb) to service_role;

commit;
