begin;

-- CasaDireta writes to its own schema. Bridge those writes into the HQ cursor
-- consumed by /api/realtime so the Central can refresh the authorized support
-- queue without exposing the CasaDireta service key to the browser.
create or replace function hq.capture_casadireta_support_realtime()
returns trigger
language plpgsql
security definer
set search_path = casadireta, hq, public
as $$
declare
  v_platform_id uuid;
  v_case_id text;
  v_resource_id text;
  v_event_type text;
begin
  select p.id into v_platform_id from hq.platforms p where p.slug = 'casadireta' limit 1;
  v_case_id := case when tg_table_name = 'support_messages' then new.case_id::text else new.id::text end;
  v_resource_id := case when tg_table_name = 'support_messages' then new.id::text else new.id::text end;
  v_event_type := case
    when tg_table_name = 'support_messages' and tg_op = 'INSERT' then 'casadireta_support_message_created'
    when tg_table_name = 'support_cases' and tg_op = 'INSERT' then 'casadireta_support_case_created'
    else 'casadireta_support_case_updated'
  end;

  insert into hq.realtime_events(platform_id, topic, resource_type, resource_id, event_type, payload)
  values (
    v_platform_id,
    'casadireta.support',
    case when tg_table_name = 'support_messages' then 'support_message' else 'support_case' end,
    v_resource_id,
    v_event_type,
    jsonb_build_object(
      'source_schema', 'casadireta',
      'source_table', tg_table_name,
      'operation', tg_op,
      'case_id', v_case_id,
      'message_id', case when tg_table_name = 'support_messages' then new.id::text else null end,
      'author_type', case when tg_table_name = 'support_messages' then new.author_type else null end,
      'is_internal', case when tg_table_name = 'support_messages' then new.is_internal else null end
    )
  );
  return new;
end;
$$;

drop trigger if exists casadireta_support_message_realtime on casadireta.support_messages;
create trigger casadireta_support_message_realtime
after insert on casadireta.support_messages
for each row execute function hq.capture_casadireta_support_realtime();

drop trigger if exists casadireta_support_case_realtime on casadireta.support_cases;
create trigger casadireta_support_case_realtime
after insert or update of status, assigned_employee_id, updated_at on casadireta.support_cases
for each row execute function hq.capture_casadireta_support_realtime();

revoke all on function hq.capture_casadireta_support_realtime() from public, anon, authenticated;
grant execute on function hq.capture_casadireta_support_realtime() to service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if to_regclass('casadireta.support_cases') is not null and not exists (
      select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'casadireta' and tablename = 'support_cases'
    ) then
      alter publication supabase_realtime add table casadireta.support_cases;
    end if;
    if to_regclass('casadireta.support_messages') is not null and not exists (
      select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'casadireta' and tablename = 'support_messages'
    ) then
      alter publication supabase_realtime add table casadireta.support_messages;
    end if;
  end if;
end;
$$;

commit;
