-- Valida o OTP do segundo aprovador sem atualizar auth.users.
-- Isto evita conflitos quando o mesmo numero ja existe noutro registo de auth.
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
  v_phone text;
  v_otp comunhao.phone_auth_otps%rowtype;
  v_token text;
  v_expected_hash text;
begin
  if v_actor is null then raise exception 'authentication_required'; end if;

  select * into v_withdrawal
  from public.admin_corporate_withdrawals
  where id = p_withdrawal_id
  for update;
  if v_withdrawal.id is null then raise exception 'withdrawal_not_found'; end if;
  if v_withdrawal.admin_id is distinct from v_actor then raise exception 'requester_session_required'; end if;
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

  v_phone := comunhao.normalize_phone_auth_number(v_approver_phone);
  v_token := regexp_replace(coalesce(p_otp, ''), '\\D', '', 'g');
  if v_phone = '' or char_length(v_token) <> 6 then raise exception 'Codigo OTP invalido.'; end if;

  update comunhao.phone_auth_otps
  set status = 'expired'
  where comunhao.normalize_phone_auth_number(phone) = v_phone
    and purpose = 'corporate_withdrawal'
    and status = 'pending'
    and expires_at < now();

  select * into v_otp
  from comunhao.phone_auth_otps
  where comunhao.normalize_phone_auth_number(phone) = v_phone
    and purpose = 'corporate_withdrawal'
    and status = 'pending'
    and expires_at > now()
  order by created_at desc
  limit 1
  for update;
  if not found then raise exception 'Nao existe nenhum codigo ativo para este numero.'; end if;

  v_expected_hash := encode(extensions.digest(v_phone || ':' || v_token, 'sha256'), 'hex');
  if v_otp.otp_hash <> v_expected_hash then
    update comunhao.phone_auth_otps
    set attempts = attempts + 1,
        status = case when attempts + 1 >= 5 then 'cancelled' else status end
    where id = v_otp.id;
    raise exception 'Codigo OTP invalido.';
  end if;

  update comunhao.phone_auth_otps
  set attempts = attempts + 1, status = 'verified', verified_at = now()
  where id = v_otp.id;
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
