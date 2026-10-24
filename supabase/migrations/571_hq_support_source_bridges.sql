begin;

-- The apps already write customer support to public.support_tickets and
-- public.support_messages. Keep the HQ queue as a read/operational mirror,
-- keyed by the source record, so an app message is never counted twice.
create unique index if not exists hq_support_tickets_external_reference_uidx
  on hq.support_tickets (external_reference)
  where external_reference is not null;

create or replace function hq.sync_public_support_ticket_to_hq()
returns trigger
language plpgsql
security definer
set search_path = public, hq
as $$
declare
  v_platform_id uuid;
  v_status text;
  v_source text := lower(coalesce(new.external_source, 'deligo'));
begin
  select id into v_platform_id from hq.platforms where slug =
    case
      when v_source like '%mestre%' then 'mestre24'
      when v_source like '%comunh%' then 'comunhao'
      when v_source like '%sarca%' then 'sarca'
      when v_source like '%market%' then 'deligo-market'
      else 'deligo'
    end
  limit 1;

  if v_platform_id is null then
    return new;
  end if;

  v_status := case lower(coalesce(new.status, 'open'))
    when 'resolved' then 'resolved'
    when 'closed' then 'closed'
    when 'escalated' then 'escalated'
    when 'waiting_customer' then 'waiting_customer'
    when 'pending' then 'in_analysis'
    when 'in_progress' then 'in_analysis'
    else 'open'
  end;

  insert into hq.support_tickets (
    platform_id, external_reference, customer_reference, subject, priority,
    status, opened_at, resolved_at, ticket_type, category, description,
    customer_name, customer_contact, resolution, updated_at
  ) values (
    v_platform_id,
    'public-support:' || new.id::text,
    new.opened_by::text,
    coalesce(nullif(trim(new.reason), ''), 'Pedido de apoio'),
    'normal',
    v_status,
    new.created_at,
    case when v_status in ('resolved', 'closed') then new.resolved_at end,
    case when new.dispute_type is not null then 'complaint' else 'question' end,
    coalesce(nullif(trim(new.dispute_type), ''), 'support'),
    new.reason,
    new.customer_name,
    coalesce(nullif(trim(new.customer_phone), ''), nullif(trim(new.customer_email), '')),
    new.resolution,
    coalesce(new.updated_at, now())
  )
  on conflict (external_reference) where external_reference is not null
  do update set
    platform_id = excluded.platform_id,
    subject = excluded.subject,
    priority = excluded.priority,
    status = excluded.status,
    description = excluded.description,
    customer_name = excluded.customer_name,
    customer_contact = excluded.customer_contact,
    resolution = excluded.resolution,
    resolved_at = excluded.resolved_at,
    updated_at = excluded.updated_at;

  return new;
end;
$$;

create or replace function hq.sync_public_support_message_to_hq()
returns trigger
language plpgsql
security definer
set search_path = public, hq
as $$
declare
  v_hq_ticket_id uuid;
begin
  select id into v_hq_ticket_id
  from hq.support_tickets
  where external_reference = 'public-support:' || new.ticket_id::text;

  if v_hq_ticket_id is not null then
    insert into hq.support_conversations (
      id, ticket_id, sender_type, sender_customer_reference,
      message, is_internal, created_at
    ) values (
      new.id,
      v_hq_ticket_id,
      case when lower(coalesce(new.sender_role, '')) in ('admin', 'agent', 'support', 'support_agent')
        then 'agent' else 'customer' end,
      new.sender_id::text,
      coalesce(new.text, ''),
      false,
      new.created_at
    ) on conflict (id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_public_support_ticket_to_hq on public.support_tickets;
create trigger trg_public_support_ticket_to_hq
after insert or update on public.support_tickets
for each row execute function hq.sync_public_support_ticket_to_hq();

drop trigger if exists trg_public_support_message_to_hq on public.support_messages;
create trigger trg_public_support_message_to_hq
after insert on public.support_messages
for each row execute function hq.sync_public_support_message_to_hq();

-- Backfill is idempotent and only mirrors existing support records; it does
-- not create notifications or alter the app's source rows.
insert into hq.support_tickets (
  platform_id, external_reference, customer_reference, subject, priority,
  status, opened_at, resolved_at, ticket_type, category, description,
  customer_name, customer_contact, resolution, updated_at
)
select
  coalesce((select id from hq.platforms where slug = case
    when lower(coalesce(st.external_source, '')) like '%mestre%' then 'mestre24'
    when lower(coalesce(st.external_source, '')) like '%comunh%' then 'comunhao'
    when lower(coalesce(st.external_source, '')) like '%sarca%' then 'sarca'
    when lower(coalesce(st.external_source, '')) like '%market%' then 'deligo-market'
    else 'deligo' end limit 1),
  '20000000-0000-0000-0000-000000000001'::uuid,
  'public-support:' || st.id::text,
  st.opened_by::text,
  coalesce(nullif(trim(st.reason), ''), 'Pedido de apoio'),
  'normal',
  case lower(coalesce(st.status, 'open')) when 'resolved' then 'resolved' when 'closed' then 'closed' when 'escalated' then 'escalated' when 'pending' then 'in_analysis' when 'in_progress' then 'in_analysis' else 'open' end,
  st.created_at,
  case when lower(st.status) in ('resolved', 'closed') then st.resolved_at end,
  case when st.dispute_type is not null then 'complaint' else 'question' end,
  coalesce(nullif(trim(st.dispute_type), ''), 'support'),
  st.reason,
  st.customer_name,
  coalesce(nullif(trim(st.customer_phone), ''), nullif(trim(st.customer_email), '')),
  st.resolution,
  coalesce(st.updated_at, now())
from public.support_tickets st
on conflict (external_reference) where external_reference is not null
do update set
  status = excluded.status,
  subject = excluded.subject,
  description = excluded.description,
  customer_name = excluded.customer_name,
  customer_contact = excluded.customer_contact,
  resolution = excluded.resolution,
  resolved_at = excluded.resolved_at,
  updated_at = excluded.updated_at;

insert into hq.support_conversations (
  id, ticket_id, sender_type, sender_customer_reference,
  message, is_internal, created_at
)
select
  sm.id,
  ht.id,
  case when lower(coalesce(sm.sender_role, '')) in ('admin', 'agent', 'support', 'support_agent')
    then 'agent' else 'customer' end,
  sm.sender_id::text,
  coalesce(sm.text, ''),
  false,
  sm.created_at
from public.support_messages sm
join hq.support_tickets ht
  on ht.external_reference = 'public-support:' || sm.ticket_id::text
on conflict (id) do nothing;

revoke all on function hq.sync_public_support_ticket_to_hq() from public, anon, authenticated;
revoke all on function hq.sync_public_support_message_to_hq() from public, anon, authenticated;
grant execute on function hq.sync_public_support_ticket_to_hq() to service_role;
grant execute on function hq.sync_public_support_message_to_hq() to service_role;

commit;


