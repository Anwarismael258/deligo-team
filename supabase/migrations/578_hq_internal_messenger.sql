begin;
create table if not exists hq.chat_conversations (
 id uuid primary key default gen_random_uuid(), kind text not null check(kind in ('direct','group')),
 title text not null check(length(title) between 1 and 120), created_by uuid not null references hq.employees(id),
 direct_key text unique, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists hq.chat_members (
 conversation_id uuid not null references hq.chat_conversations(id) on delete cascade,
 employee_id uuid not null references hq.employees(id), last_read_at timestamptz not null default '-infinity',
 primary key(conversation_id,employee_id)
);
create table if not exists hq.chat_messages (
 id uuid primary key default gen_random_uuid(), conversation_id uuid not null references hq.chat_conversations(id) on delete cascade,
 sender_id uuid not null references hq.employees(id), body text not null default '' check(length(body)<=10000),
 reply_to uuid references hq.chat_messages(id), meeting_url text, client_id uuid not null,
 created_at timestamptz not null default now(), unique(sender_id,client_id)
);
create table if not exists hq.chat_attachments (
 id uuid primary key default gen_random_uuid(), conversation_id uuid not null references hq.chat_conversations(id) on delete cascade,
 message_id uuid references hq.chat_messages(id), uploaded_by uuid not null references hq.employees(id),
 storage_path text not null unique, file_name text not null, mime_type text not null,
 size_bytes bigint not null check(size_bytes between 1 and 3145728), created_at timestamptz not null default now()
);
create index if not exists chat_members_employee on hq.chat_members(employee_id,conversation_id);
create index if not exists chat_messages_timeline on hq.chat_messages(conversation_id,created_at desc,id desc);
create index if not exists chat_attachments_message on hq.chat_attachments(message_id);
do $$ declare t text; begin
 foreach t in array array['chat_conversations','chat_members','chat_messages','chat_attachments'] loop
  execute format('alter table hq.%I enable row level security',t);
  execute format('revoke all on hq.%I from public,anon,authenticated',t);
  execute format('grant all on hq.%I to service_role',t);
 end loop;
end $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('hq-internal-inbox','hq-internal-inbox',false,3145728,array['image/jpeg','image/png','image/webp','application/pdf','text/plain','text/csv','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.openxmlformats-officedocument.presentationml.presentation','audio/mpeg','audio/ogg','video/mp4'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create or replace function hq.chat_create_v1(p_actor uuid,p_recipients uuid[],p_title text default '',p_all boolean default false) returns uuid
language plpgsql security definer set search_path=hq,public as $$
declare ids uuid[]; cid uuid; k text; direct boolean;
begin
 if not exists(select 1 from employees where id=p_actor and status='active') then raise exception 'Sem acesso activo'; end if;
 if p_all then select array_agg(id order by id) into ids from employees where status='active';
 else select array_agg(distinct x order by x) into ids from unnest(array_append(coalesce(p_recipients,'{}'),p_actor)) x;
 end if;
 if cardinality(ids)<2 or cardinality(ids)>500 then raise exception 'Seleccione entre 1 e 499 destinatários'; end if;
 if exists(select 1 from unnest(ids) x where not exists(select 1 from employees e where e.id=x and e.status='active')) then raise exception 'Destinatário sem acesso activo'; end if;
 direct:=cardinality(ids)=2 and not p_all and nullif(trim(p_title),'') is null;
 if direct then k:=array_to_string(ids,':'); end if;
 insert into chat_conversations(kind,title,created_by,direct_key)
 values(case when direct then 'direct' else 'group' end,case when direct then 'Conversa' else coalesce(nullif(left(trim(p_title),120),''),'Equipa DeliGo') end,p_actor,k)
 on conflict(direct_key) do update set direct_key=excluded.direct_key returning id into cid;
 insert into chat_members(conversation_id,employee_id) select cid,x from unnest(ids) x on conflict do nothing;
 return cid;
end $$;

create or replace function hq.chat_list_v1(p_actor uuid) returns jsonb
language sql stable security definer set search_path=hq,public as $$
 select coalesce(jsonb_agg(row_to_json(q) order by q.updated_at desc),'[]'::jsonb) from (
 select c.*, (select count(*) from chat_messages m where m.conversation_id=c.id and m.sender_id<>p_actor and m.created_at>own.last_read_at) unread,
 (select left(m.body,140) from chat_messages m where m.conversation_id=c.id order by m.created_at desc,m.id desc limit 1) preview,
 (select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'name',e.display_name,'active',e.status='active','lastReadAt',case when cm.last_read_at='-infinity'::timestamptz then null else cm.last_read_at end)),'[]'::jsonb) from chat_members cm join employees e on e.id=cm.employee_id where cm.conversation_id=c.id) members
 from chat_conversations c join chat_members own on own.conversation_id=c.id and own.employee_id=p_actor
 where exists(select 1 from employees where id=p_actor and status='active')
 order by c.updated_at desc limit 200) q
$$;

create or replace function hq.chat_send_v1(p_actor uuid,p_conversation uuid,p_body text,p_client uuid,p_reply uuid default null,p_files uuid[] default '{}',p_meeting text default null) returns hq.chat_messages
language plpgsql security definer set search_path=hq,public as $$
declare msg chat_messages; existing chat_messages; n integer;
begin
 if not exists(select 1 from chat_members cm join employees e on e.id=cm.employee_id where cm.conversation_id=p_conversation and e.id=p_actor and e.status='active') then raise exception 'Sem acesso à conversa'; end if;
 select * into existing from chat_messages where sender_id=p_actor and client_id=p_client;
 if found then
  if existing.conversation_id<>p_conversation then raise exception 'Identificador inválido'; end if;
  return existing;
 end if;
 if length(coalesce(p_body,''))>10000 or (nullif(trim(p_body),'') is null and cardinality(p_files)=0 and p_meeting is null) then raise exception 'Mensagem inválida'; end if;
 if cardinality(p_files)>5 then raise exception 'Máximo de 5 anexos'; end if;
 if p_reply is not null and not exists(select 1 from chat_messages where id=p_reply and conversation_id=p_conversation) then raise exception 'Resposta fora da conversa'; end if;
 -- Serialise sends for one conversation, including attachment claims and retry IDs.
 perform 1 from chat_conversations where id=p_conversation for update;
 select * into existing from chat_messages where sender_id=p_actor and client_id=p_client;
 if found then return existing; end if;
 select count(*) into n from chat_attachments where id=any(p_files) and conversation_id=p_conversation and uploaded_by=p_actor and message_id is null;
 if n<>cardinality(p_files) then raise exception 'Anexo inválido'; end if;
 insert into chat_messages(conversation_id,sender_id,body,reply_to,client_id,meeting_url,created_at)
 values(p_conversation,p_actor,trim(coalesce(p_body,'')),p_reply,p_client,p_meeting,clock_timestamp()) returning * into msg;
 update chat_attachments set message_id=msg.id where id=any(p_files);
 update chat_conversations set updated_at=msg.created_at where id=p_conversation;
 insert into notifications(employee_id,type,title,body,target_url,source_type,source_id)
 select cm.employee_id,'internal_message',case when p_meeting is null then 'Nova mensagem interna' else 'Convite para reunião' end,
 'Recebeu uma mensagem na Inbox interna.','/inbox-interna?conversation='||p_conversation,'internal_message',p_conversation::text
 from chat_members cm join employees e on e.id=cm.employee_id where cm.conversation_id=p_conversation and cm.employee_id<>p_actor and e.status='active';
 return msg;
end $$;

create or replace function hq.chat_read_v1(p_actor uuid,p_conversation uuid,p_message uuid) returns void
language plpgsql security definer set search_path=hq,public as $$
declare stamp timestamptz;
begin
 if not exists(select 1 from chat_members cm join employees e on e.id=cm.employee_id where cm.conversation_id=p_conversation and e.id=p_actor and e.status='active') then raise exception 'Sem acesso'; end if;
 select created_at into stamp from chat_messages where id=p_message and conversation_id=p_conversation;
 if stamp is null then raise exception 'Mensagem inválida'; end if;
 update chat_members set last_read_at=greatest(last_read_at,stamp) where conversation_id=p_conversation and employee_id=p_actor;
 update notifications set read_at=coalesce(read_at,now()) where employee_id=p_actor and source_type='internal_message' and source_id=p_conversation::text and created_at<=stamp;
end $$;
revoke all on function hq.chat_create_v1(uuid,uuid[],text,boolean),hq.chat_list_v1(uuid),hq.chat_send_v1(uuid,uuid,text,uuid,uuid,uuid[],text),hq.chat_read_v1(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function hq.chat_create_v1(uuid,uuid[],text,boolean),hq.chat_list_v1(uuid),hq.chat_send_v1(uuid,uuid,text,uuid,uuid,uuid[],text),hq.chat_read_v1(uuid,uuid,uuid) to service_role;
notify pgrst,'reload schema';
commit;
