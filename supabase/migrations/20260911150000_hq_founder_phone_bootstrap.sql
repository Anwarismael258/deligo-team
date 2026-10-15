begin;

-- Bootstrap dos dois primeiros acessos da Central HQ.
-- Os números são mantidos em formato E.164 e ligados aos códigos canónicos.
update hq.employees
set phone_e164 = case employee_code
  when 'DG-0001' then '+258841130015'
  when 'DG-0002' then '+258877688695'
end,
updated_at = now()
where employee_code in ('DG-0001', 'DG-0002')
  and status <> 'offboarded';

create unique index if not exists hq_employees_active_phone_unique
  on hq.employees(phone_e164)
  where status <> 'offboarded';

commit;
