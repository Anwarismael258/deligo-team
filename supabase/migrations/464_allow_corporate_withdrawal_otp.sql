begin;

-- Corporate withdrawals use the existing phone OTP table.  Keep the
-- purpose explicit so the OTP cannot be confused with a normal login OTP.
alter table comunhao.phone_auth_otps
  drop constraint if exists phone_auth_otps_purpose_check;

alter table comunhao.phone_auth_otps
  add constraint phone_auth_otps_purpose_check
  check (purpose = any (array['signup'::text, 'login'::text, 'corporate_withdrawal'::text]));

commit;
