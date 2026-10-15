-- Controlled Payroll lifecycle. No provider payout is initiated by these RPCs.
create or replace function public.hq_calculate_payroll_v1(p_run_id uuid, p_actor uuid)
returns jsonb language plpgsql security definer set search_path=hq,public as $$
declare r payroll_runs%rowtype; n integer;
begin
  select * into r from hq.payroll_runs where id=p_run_id for update;
  if not found or r.status not in ('draft','calculated') then raise exception 'payroll_not_calculable'; end if;
  insert into hq.payroll_lines(payroll_run_id,employee_id,base_salary,allowances,bonuses,overtime,other_credits,absences_deductions,other_deductions,status)
  select r.id,e.id,coalesce(x.gross_amount,0),0,0,0,0,coalesce(x.deductions,0),0,'calculated'
  from hq.employees e left join lateral (select gross_amount,deductions from hq.hr_payroll_records p where p.employee_id=e.id and p.period_start=r.period_start and p.period_end=r.period_end order by p.created_at desc limit 1) x on true
  where e.status='active'
  on conflict(payroll_run_id,employee_id) do update set base_salary=excluded.base_salary,absences_deductions=excluded.absences_deductions,status='calculated',updated_at=now();
  get diagnostics n=row_count;
  update hq.payroll_runs set status='calculated',total_amount=coalesce((select sum(net_amount) from hq.payroll_lines where payroll_run_id=r.id and status='calculated'),0),updated_at=now() where id=r.id;
  return jsonb_build_object('run_id',r.id,'status','calculated','lines',n,'actor',p_actor);
end $$;

create or replace function public.hq_validate_payroll_v1(p_run_id uuid, p_actor uuid)
returns jsonb language plpgsql security definer set search_path=hq,public as $$
begin
  if not exists(select 1 from hq.payroll_runs where id=p_run_id and status='calculated') then raise exception 'payroll_not_calculated'; end if;
  update hq.payroll_runs set status='validated',validated_by=p_actor,updated_at=now() where id=p_run_id;
  update hq.payroll_lines set status='validated',updated_at=now() where payroll_run_id=p_run_id and status='calculated';
  return jsonb_build_object('run_id',p_run_id,'status','validated','validated_by',p_actor);
end $$;

create or replace function public.hq_submit_payroll_v1(p_run_id uuid, p_actor uuid)
returns jsonb language plpgsql security definer set search_path=hq,public as $$
begin
  if not exists(select 1 from hq.payroll_runs where id=p_run_id and status='validated') then raise exception 'payroll_not_validated'; end if;
  update hq.payroll_runs set status='submitted_to_finance',submitted_to_finance_at=now(),updated_at=now() where id=p_run_id;
  return jsonb_build_object('run_id',p_run_id,'status','submitted_to_finance','submitted_by',p_actor);
end $$;

create or replace function public.hq_approve_payroll_v1(p_run_id uuid, p_actor uuid)
returns jsonb language plpgsql security definer set search_path=hq,public as $$
begin
  if not exists(select 1 from hq.payroll_runs where id=p_run_id and status in ('submitted_to_finance','pending_approval')) then raise exception 'payroll_not_pending_approval'; end if;
  if exists(select 1 from hq.payroll_runs where id=p_run_id and prepared_by=p_actor) then raise exception 'maker_cannot_approve'; end if;
  update hq.payroll_runs set status='approved',approved_by=p_actor,updated_at=now() where id=p_run_id;
  update hq.payroll_lines set status='approved',updated_at=now() where payroll_run_id=p_run_id and status='validated';
  return jsonb_build_object('run_id',p_run_id,'status','approved','approved_by',p_actor,'payout_started',false);
end $$;

revoke all on function public.hq_calculate_payroll_v1(uuid,uuid),public.hq_validate_payroll_v1(uuid,uuid),public.hq_submit_payroll_v1(uuid,uuid),public.hq_approve_payroll_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function public.hq_calculate_payroll_v1(uuid,uuid),public.hq_validate_payroll_v1(uuid,uuid),public.hq_submit_payroll_v1(uuid,uuid),public.hq_approve_payroll_v1(uuid,uuid) to service_role;
