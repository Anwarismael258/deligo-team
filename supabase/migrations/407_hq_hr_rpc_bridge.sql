begin;
create or replace function public.hq_create_hr_record_v1(p_resource text,p_record jsonb) returns jsonb
language plpgsql security definer set search_path=hq,public as $$
declare result jsonb;
begin
 if p_resource='hr_payroll_records' then
  insert into hq.hr_payroll_records(employee_id,period_start,period_end,gross_amount,deductions,currency,status)
  select x.employee_id,x.period_start,x.period_end,x.gross_amount,x.deductions,x.currency,x.status
  from jsonb_to_record(p_record) x(employee_id uuid,period_start date,period_end date,gross_amount numeric,deductions numeric,currency text,status text)
  returning to_jsonb(hr_payroll_records.*) into result;
 elsif p_resource='hr_employee_events' then
  insert into hq.hr_employee_events(employee_id,event_type,title,occurred_on,status)
  select x.employee_id,x.event_type,x.title,x.occurred_on,x.status
  from jsonb_to_record(p_record) x(employee_id uuid,event_type text,title text,occurred_on date,status text)
  returning to_jsonb(hr_employee_events.*) into result;
 else raise exception 'HR_RESOURCE_NOT_ALLOWED'; end if;
 return result;
end $$;
revoke all on function public.hq_create_hr_record_v1(text,jsonb) from public,anon,authenticated;
grant execute on function public.hq_create_hr_record_v1(text,jsonb) to service_role;
commit;
