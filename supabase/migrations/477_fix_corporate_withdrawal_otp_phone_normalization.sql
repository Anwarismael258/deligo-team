-- Corporate withdrawal OTPs must use the same canonical phone format as
-- comunhao.verify_phone_auth_otp (digits only). Employee records remain E.164.
create or replace function public.hq_send_corporate_withdrawal_otp_v1(p_withdrawal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, hq, comunhao, auth, extensions, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_withdrawal public.admin_corporate_withdrawals%rowtype;
  v_approval public.admin_corporate_withdrawal_approvals%rowtype;
  v_phone text;
  v_code text;
  v_hash text;
  v_otp_id uuid;
begin
  select * into v_withdrawal
  from public.admin_corporate_withdrawals
  where id = p_withdrawal_id
  for update;
  if v_withdrawal.id is null then raise exception 'withdrawal_not_found'; end if;
  if v_withdrawal.admin_id <> v_actor then raise exception 'requester_session_required'; end if;
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

  select comunhao.normalize_phone_auth_number(phone_e164)
  into v_phone
  from hq.employees
  where auth_user_id = v_approval.approver_id
    and status = 'active';
  if coalesce(v_phone, '') = '' then raise exception 'approver_phone_not_available'; end if;

  -- Cancel both legacy E.164 rows and canonical digit-only rows for this phone.
  update comunhao.phone_auth_otps
  set status = 'cancelled'
  where comunhao.normalize_phone_auth_number(phone) = v_phone
    and status = 'pending';

  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  v_hash := encode(extensions.digest(v_phone || ':' || v_code, 'sha256'), 'hex');
  insert into comunhao.phone_auth_otps (
    auth_user_id, phone, purpose, otp_hash, attempts, status, last_sent_at, expires_at
  ) values (
    v_approval.approver_id, v_phone, 'corporate_withdrawal', v_hash, 0,
    'pending', now(), now() + interval '10 minutes'
  ) returning id into v_otp_id;

  perform comunhao.send_sms_via_mozesms(
    v_phone,
    format(
      'DeliGo: pedido de levantamento de %s MT. Solicitante: %s. Codigo OTP: %s. Valido por 10 minutos.',
      to_char(v_withdrawal.amount, 'FM999999990.00'),
      case when v_withdrawal.requester_role = 'SUPER_ADMIN' then 'Admin' else 'Financas' end,
      v_code
    )
  );

  update public.admin_corporate_withdrawal_approvals
  set otp_challenge_id = v_otp_id::text,
      otp_expires_at = now() + interval '10 minutes',
      updated_at = now()
  where id = v_approval.id;

  return jsonb_build_object(
    'success', true,
    'withdrawal_id', p_withdrawal_id,
    'amount', v_withdrawal.amount,
    'approver_id', v_approval.approver_id,
    'expires_in_seconds', 600
  );
end;
$$;

revoke all on function public.hq_send_corporate_withdrawal_otp_v1(uuid) from public, anon;
grant execute on function public.hq_send_corporate_withdrawal_otp_v1(uuid) to authenticated, service_role;

-- Also make validation tolerant of older rows that still contain E.164 text.
create or replace function comunhao.verify_phone_auth_otp(p_phone text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = comunhao, public, auth, extensions, pg_temp
as $$
declare
  normalized_phone text := comunhao.normalize_phone_auth_number(p_phone);
  normalized_token text := comunhao.normalize_phone_auth_number(p_token);
  otp_row comunhao.phone_auth_otps%rowtype;
  expected_hash text;
  verified_user_id uuid;
  merged_metadata jsonb;
begin
  if normalized_phone = '' then raise exception 'Numero de telefone invalido.'; end if;
  if char_length(normalized_token) <> 6 then raise exception 'O codigo OTP deve ter 6 digitos.'; end if;

  update comunhao.phone_auth_otps
  set status = 'expired'
  where comunhao.normalize_phone_auth_number(phone) = normalized_phone
    and status = 'pending'
    and expires_at < now();

  select * into otp_row
  from comunhao.phone_auth_otps
  where comunhao.normalize_phone_auth_number(phone) = normalized_phone
    and status = 'pending'
  order by created_at desc
  limit 1
  for update;
  if not found then raise exception 'Nao existe nenhum codigo ativo para este numero.'; end if;

  expected_hash := encode(extensions.digest(normalized_phone || ':' || normalized_token, 'sha256'), 'hex');
  if otp_row.otp_hash <> expected_hash then
    update comunhao.phone_auth_otps
    set attempts = attempts + 1,
        status = case when attempts + 1 >= 5 then 'cancelled' else status end
    where id = otp_row.id;
    raise exception 'Codigo OTP invalido.';
  end if;

  update comunhao.phone_auth_otps
  set attempts = attempts + 1, status = 'verified', verified_at = now()
  where id = otp_row.id
  returning auth_user_id into verified_user_id;

  select coalesce(raw_user_meta_data, '{}'::jsonb) into merged_metadata
  from auth.users where id = verified_user_id limit 1;
  merged_metadata := merged_metadata || jsonb_build_object(
    'phone', normalized_phone, 'phone_verified', true, 'phone_verified_at', now()
  );
  update auth.users
  set phone = normalized_phone, phone_confirmed_at = now(),
      raw_user_meta_data = merged_metadata, updated_at = now()
  where id = verified_user_id;
  return jsonb_build_object('success', true, 'user_id', verified_user_id, 'phone', normalized_phone);
end;
$$;

revoke all on function comunhao.verify_phone_auth_otp(text, text) from public, anon, authenticated;
grant execute on function comunhao.verify_phone_auth_otp(text, text) to service_role;

notify pgrst, 'reload schema';
