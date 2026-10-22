-- O segundo aprovador nao precisa manter uma sessao online.
-- O OTP enviado ao telefone do segundo aprovador e a prova da aprovacao.
-- A confirmacao deve ser feita pela sessao do trabalhador que abriu o pedido.
create or replace function public.hq_confirm_corporate_withdrawal_v1(
  p_withdrawal_id uuid,
  p_otp text
)
returns jsonb
language plpgsql
security definer
set search_path = public, hq, comunhao, auth, extensions, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_approval public.admin_corporate_withdrawal_approvals%rowtype;
  v_withdrawal public.admin_corporate_withdrawals%rowtype;
  v_approver_phone text;
begin
  if v_actor is null then raise exception 'authentication_required'; end if;

  select * into v_withdrawal
  from public.admin_corporate_withdrawals
  where id = p_withdrawal_id
  for update;
  if v_withdrawal.id is null then raise exception 'withdrawal_not_found'; end if;
  if v_withdrawal.admin_id is distinct from v_actor then
    raise exception 'requester_session_required';
  end if;
  if v_withdrawal.status <> 'pending_approval'
     or v_withdrawal.approval_status <> 'pending_second_approval' then
    raise exception 'withdrawal_not_pending';
  end if;

  select * into v_approval
  from public.admin_corporate_withdrawal_approvals
  where withdrawal_id = p_withdrawal_id
    and status = 'pending'
    and otp_expires_at > now()
  for update;
  if v_approval.id is null then raise exception 'approval_not_pending_or_expired'; end if;
  if v_withdrawal.second_approver_id is distinct from v_approval.approver_id then
    raise exception 'second_approver_mismatch';
  end if;

  select phone_e164 into v_approver_phone
  from hq.employees
  where auth_user_id = v_approval.approver_id
    and status = 'active';
  if v_approver_phone is null then raise exception 'approver_phone_not_available'; end if;

  -- Validar o OTP do segundo aprovador, sem exigir a sessao dele.
  perform comunhao.verify_phone_auth_otp(v_approver_phone, p_otp);

  update public.admin_corporate_withdrawal_approvals
  set status = 'verified', verified_at = now(), updated_at = now()
  where id = v_approval.id;
  update public.admin_corporate_withdrawals
  set status = 'approved', approval_status = 'approved', approved_at = now(), updated_at = now()
  where id = v_withdrawal.id;

  return jsonb_build_object(
    'success', true,
    'withdrawal_id', p_withdrawal_id,
    'status', 'approved',
    'approval_status', 'approved',
    'otp_verified', true,
    'requested_by', v_actor,
    'approver_id', v_approval.approver_id
  );
end;
$$;

revoke all on function public.hq_confirm_corporate_withdrawal_v1(uuid, text) from public, anon;
grant execute on function public.hq_confirm_corporate_withdrawal_v1(uuid, text) to authenticated, service_role;

notify pgrst, 'reload schema';
