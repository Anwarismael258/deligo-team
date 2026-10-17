begin;

-- Dedicated non-login employee used only to attribute inbound WhatsApp events.
insert into hq.employees (
  id, employee_code, legal_entity_id, department_id, display_name, job_title, status
) values (
  '40000000-0000-0000-0000-000000000020',
  'SYS-WHATSAPP',
  '10000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000010',
  'WhatsApp Integration',
  'System Integration',
  'active'
)
on conflict (employee_code) do update set
  display_name = excluded.display_name,
  job_title = excluded.job_title,
  status = 'active';

alter table hq.support_tickets
  add column if not exists source_channel text not null default 'central';

alter table hq.support_conversations
  add column if not exists source_channel text not null default 'central',
  add column if not exists external_message_id text;

create index if not exists support_tickets_channel_contact_updated_idx
  on hq.support_tickets (source_channel, customer_contact, updated_at desc);

create unique index if not exists support_conversations_external_message_id_uidx
  on hq.support_conversations (external_message_id)
  where external_message_id is not null;

comment on column hq.support_tickets.source_channel is
  'Origin channel for the unified support inbox, e.g. central or whatsapp.';
comment on column hq.support_conversations.source_channel is
  'Channel where the conversation message originated or was sent.';
comment on column hq.support_conversations.external_message_id is
  'Provider message identifier used for webhook idempotency.';

commit;
