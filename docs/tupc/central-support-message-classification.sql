CREATE OR REPLACE FUNCTION hq.sync_deligo_support_message_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'hq'
AS $function$
declare
  v_hq_ticket_id uuid;
begin
  select id into v_hq_ticket_id
  from hq.support_tickets
  where external_reference = 'deligo:support:' || new.ticket_id::text;

  if v_hq_ticket_id is not null then
    insert into hq.support_conversations (
      id, ticket_id, sender_type, sender_customer_reference,
      message, is_internal, created_at
    ) values (
      new.id, v_hq_ticket_id,
      case when lower(coalesce(new.sender_role, '')) in ('admin','agent','support','support_agent','super_admin','finance','supervisor','operations','customer_support') then 'agent' else 'customer' end,
      new.sender_id::text, new.text, false, new.created_at
    ) on conflict (id) do nothing;
  end if;
  return new;
end;
$function$
;
