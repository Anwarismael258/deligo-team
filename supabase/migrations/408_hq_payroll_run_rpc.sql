begin;
create or replace function public.hq_create_payroll_run_v1(p_label text,p_start date,p_end date,p_prepared_by uuid) returns jsonb language plpgsql security definer set search_path=hq,public as $$ declare r jsonb; begin insert into hq.payroll_runs(period_label,period_start,period_end,status,idempotency_key,prepared_by) values(p_label,p_start,p_end,'draft','payroll:'||p_start||':'||p_end,p_prepared_by) returning to_jsonb(payroll_runs.*) into r; return r; end $$;
create or replace function public.hq_payroll_runs_v1() returns jsonb language sql security definer set search_path=hq,public as $$ select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (select * from hq.payroll_runs order by created_at desc limit 50) x $$;
revoke all on function public.hq_create_payroll_run_v1(text,date,date,uuid),public.hq_payroll_runs_v1() from public,anon,authenticated;
grant execute on function public.hq_create_payroll_run_v1(text,date,date,uuid),public.hq_payroll_runs_v1() to service_role;
commit;
