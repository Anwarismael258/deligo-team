create or replace function hq.notify_payroll_approval_v1() returns trigger language plpgsql security definer set search_path=hq,public as $$
begin
  if new.status='approved' and coalesce(old.status,'')<>'approved' then
    insert into hq.notifications(employee_id,type,title,body,target_url,priority,source_type,source_id,dedupe_key)
    select l.employee_id,'payroll_approved','Folha salarial aprovada','A sua folha salarial foi aprovada e está em processamento. O pagamento só será confirmado após o gateway e a reconciliação.','/recursos-humanos','normal','payroll_run',new.id,'payroll-approved:'||new.id||':'||l.employee_id
    from hq.payroll_lines l where l.payroll_run_id=new.id
    on conflict do nothing;
    insert into hq.notification_deliveries(notification_id,employee_id,channel,provider,template_code,payload)
    select n.id,n.employee_id,'sms','moz_esms','PAYROLL_APPROVED_NOTICE',jsonb_build_object('message','A sua folha salarial foi aprovada e está em processamento na Central DeliGo Triunfal.')
    from hq.notifications n where n.source_type='payroll_run' and n.source_id=new.id and n.type='payroll_approved'
    on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists trg_payroll_approval_notice on hq.payroll_runs;
create trigger trg_payroll_approval_notice after update of status on hq.payroll_runs for each row execute function hq.notify_payroll_approval_v1();
comment on function hq.notify_payroll_approval_v1() is 'Approval notification only; never initiates a provider payout.';
notify pgrst,'reload schema';
