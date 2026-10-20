begin;

-- DG-0002 is Sara Vitorino Feniosse Ismael. Keep the HQ login phone
-- aligned with the canonical account used by the OTP flow.
update hq.employees
set phone_e164 = '+258877688695',
    updated_at = now()
where employee_code = 'DG-0002'
  and display_name = 'Sara Vitorino Feniosse Ismael'
  and status <> 'offboarded';

commit;
