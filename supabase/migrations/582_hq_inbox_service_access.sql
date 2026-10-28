begin;
-- PostgREST must be able to resolve the service-only messenger RPCs.
grant usage on schema hq to service_role;
grant select,insert,update,delete on hq.chat_conversations,hq.chat_members,hq.chat_messages,hq.chat_attachments to service_role;
notify pgrst,'reload schema';
commit;
