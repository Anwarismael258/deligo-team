create or replace function hq.notify_microcredit_intake_v1() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into hq.notifications(employee_id,type,source_type,source_id,title,body,target_url,priority,dedupe_key,action_required)
 select e.id,'microcredit_application_received','microcredit_application',new.id::text,'Novo pedido de microcrédito',coalesce(new.reference,'Pedido recebido')||' · Aguardando análise da equipa financeira.','/microcredito?application='||new.id::text,'high','microcredit-new:'||new.id::text,true
 from hq.employees e join hq.roles r on r.id=e.primary_role_id
 where e.status='active' and (e.valid_until is null or e.valid_until>now()) and r.code in ('SUPER_ADMIN','FINANCE')
 on conflict(employee_id,dedupe_key) do nothing;
 return new;
end $$;
revoke all on function hq.notify_microcredit_intake_v1() from public,anon,authenticated;
create trigger notify_hq_microcredit_intake after insert on public.loan_applications for each row execute function hq.notify_microcredit_intake_v1();
-- Deliver the currently pending intake too; repeated deployment never duplicates it.
insert into hq.notifications(employee_id,type,source_type,source_id,title,body,target_url,priority,dedupe_key,action_required)
select e.id,'microcredit_application_received','microcredit_application',a.id::text,'Novo pedido de microcrédito',coalesce(a.reference,'Pedido recebido')||' · Aguardando análise da equipa financeira.','/microcredito?application='||a.id::text,'high','microcredit-new:'||a.id::text,true
from public.loan_applications a cross join hq.employees e join hq.roles r on r.id=e.primary_role_id
where a.status='pendente' and e.status='active' and (e.valid_until is null or e.valid_until>now()) and r.code in ('SUPER_ADMIN','FINANCE')
on conflict(employee_id,dedupe_key) do nothing;
