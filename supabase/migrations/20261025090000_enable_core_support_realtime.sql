begin;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and to_regclass('core.support_case_messages') is not null
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'core'
         and tablename = 'support_case_messages'
     ) then
    alter publication supabase_realtime add table core.support_case_messages;
  end if;
end $$;

commit;
