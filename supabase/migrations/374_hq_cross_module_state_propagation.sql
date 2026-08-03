begin;

alter table hq.contracts add column if not exists workflow_case_id uuid references hq.workflow_cases(id);
create index if not exists idx_hq_contracts_workflow_case on hq.contracts(workflow_case_id) where workflow_case_id is not null;

create or replace function hq.propagate_finance_payment_to_procurement() returns trigger
language plpgsql security definer set search_path=hq,public as $$
declare purchase_id uuid;case_id uuid;
begin
 if old.status is distinct from new.status and new.status='paid' then
  select po.purchase_request_id into purchase_id
  from hq.procurement_invoices pi join hq.purchase_orders po on po.id=pi.purchase_order_id
  where pi.payment_request_id=new.id order by pi.created_at desc limit 1;
  if purchase_id is not null then
   update hq.procurement_invoices set status='paid' where payment_request_id=new.id and status<>'paid';
   update hq.purchase_requests set status='paid',updated_at=now() where id=purchase_id and status<>'paid';
   insert into hq.procurement_history(purchase_request_id,event_type,description,actor_employee_id,metadata)
   values(purchase_id,'payment_confirmed','Pagamento confirmado por Finanças',new.approved_by,jsonb_build_object('payment_request_id',new.id,'paid_at',new.paid_at));
   select workflow_case_id into case_id from hq.purchase_requests where id=purchase_id;
   insert into hq.realtime_events(platform_id,workflow_case_id,topic,resource_type,resource_id,event_type,payload)
   values(new.platform_id,case_id,'procurement','purchase_requests',purchase_id::text,'payment_confirmed',jsonb_build_object('status','paid','payment_request_id',new.id));
  end if;
 end if;
 return new;
end $$;
drop trigger if exists trg_hq_payment_to_procurement on hq.payment_requests;
create trigger trg_hq_payment_to_procurement after update of status on hq.payment_requests for each row execute function hq.propagate_finance_payment_to_procurement();

commit;
