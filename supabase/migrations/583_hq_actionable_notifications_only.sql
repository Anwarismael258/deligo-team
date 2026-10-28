begin;
-- Preserve the audit log; suppress routine activity only in the notification queue.
create or replace function hq.notification_incoming_only_v1() returns trigger
language plpgsql set search_path=hq,public as $$
declare t text:=lower(coalesce(new.type,'')); s text:=lower(coalesce(new.source_type,'')); txt text;
begin
 if t=any(array['manual_communication','internal_message','support_message','wallet_transfer_received','wallet_transfer_sent','balance_confirmation','deposit_confirmed'])
 or s=any(array['manual_communication','internal_message','support_message']) then return new; end if;
 if s=any(array['audit','audit_log','task','process_event','financial_event']) then return null; end if;
 txt:=lower(concat_ws(' ',t,new.title,new.body));
 if txt~'(new|novo|nova|created|submitted|received|recebido|recebida|criado|criada)'
 and txt~'(order|pedido|trip|ride|viagem|kyc|verifica|marketing|support_message)' then return new; end if;
 return null;
end $$;
drop trigger if exists notification_incoming_only on hq.notifications;
create trigger notification_incoming_only before insert on hq.notifications
for each row execute function hq.notification_incoming_only_v1();
commit;

begin;
create or replace function hq.notify_confirmed_employee_transfer_v1() returns trigger
language plpgsql set search_path=hq,public as $$
begin
 if new.status<>'settled' then return new; end if;
 insert into hq.notifications(employee_id,type,title,body,source_type,source_id,dedupe_key,target_url)
 select recipient,'balance_confirmation','Transferência confirmada',
 new.amount::text||' '||new.currency||' · saldo transferido com sucesso.',
 'balance_confirmation',new.id::text,'transfer-confirmed:'||new.id::text||':'||recipient::text,'/meu-perfil'
 from (select distinct unnest(array[new.actor_employee_id,new.target_employee_id]) recipient) q
 where recipient is not null
 on conflict(employee_id,dedupe_key) do nothing;
 return new;
end $$;
drop trigger if exists notify_confirmed_employee_transfer on hq.employee_wallet_transfers;
create trigger notify_confirmed_employee_transfer after insert on hq.employee_wallet_transfers
for each row execute function hq.notify_confirmed_employee_transfer_v1();
commit;
