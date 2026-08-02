begin;

create or replace function hq.sync_support_workflow_response() returns trigger
language plpgsql security definer set search_path=hq,public as $$
declare v_ticket_id uuid; v_assignment_id uuid;
begin
  if new.step_type<>'support_response' or new.status not in('completed','rejected') or new.status=old.status then return new; end if;
  v_ticket_id:=new.target_id::uuid;
  select id into v_assignment_id from hq.support_department_assignments where ticket_id=v_ticket_id and department_id=new.department_id and status in('pending','accepted') order by created_at desc limit 1;
  insert into hq.support_conversations(ticket_id,sender_type,sender_employee_id,message,is_internal)
  values(v_ticket_id,'system',null,coalesce(new.result,case when new.status='completed' then 'Departamento concluiu a análise.' else 'Departamento rejeitou o encaminhamento.' end),true);
  if v_assignment_id is not null then update hq.support_department_assignments set status=case when new.status='completed' then 'responded' else 'cancelled' end,response=new.result,responded_at=now() where id=v_assignment_id;end if;
  insert into hq.support_history(ticket_id,event_type,description,metadata)
  values(v_ticket_id,'department_response',coalesce(new.result,'Resposta departamental registada'),jsonb_build_object('department_id',new.department_id,'workflow_step_id',new.id,'decision',new.status));
  update hq.support_tickets set status=case when status='escalated' then 'in_analysis' else status end,updated_at=now() where id=v_ticket_id;
  return new;
end $$;
drop trigger if exists trg_sync_support_workflow_response on hq.workflow_steps;
create trigger trg_sync_support_workflow_response after update of status on hq.workflow_steps for each row execute function hq.sync_support_workflow_response();
revoke all on function hq.sync_support_workflow_response() from public,anon,authenticated;
grant execute on function hq.sync_support_workflow_response() to service_role;

commit;
