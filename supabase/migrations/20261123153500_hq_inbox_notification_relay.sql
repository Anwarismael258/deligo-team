-- Relay new corporate inbox messages into the permissioned HQ notification feed.
-- Existing read states and messages are preserved; only future inserts are relayed.
create or replace function public.hq_notify_inbox_message()
returns trigger
language plpgsql
security definer
set search_path=public,hq,pg_temp
as $$
declare
  row_data jsonb := to_jsonb(new);
  area_text text := lower(coalesce(row_data->>'area',''));
  source_id_text text := row_data->>'id';
  required_permissions text[];
  notification_title text;
begin
  if area_text = 'geral' then
    required_permissions := array['support.view'];
    notification_title := 'Novo email recebido';
  elsif area_text = 'comercial' then
    required_permissions := array['marketing.view'];
    notification_title := 'Novo email comercial recebido';
  elsif area_text = 'carreiras' then
    required_permissions := array['hr.viewEmployees'];
    notification_title := 'Nova candidatura ou email de carreiras';
  else
    return new;
  end if;

  perform hq.notify_permissioned_event(
    'inbox-message:'||coalesce(source_id_text,md5(row_data::text)),
    'inbox_message',
    notification_title,
    concat_ws(' · ',nullif(row_data->>'subject',''),nullif(row_data->>'from_name',''),nullif(row_data->>'from_email','')),
    null,
    '/caixa-de-entrada',
    required_permissions,
    'message',
    true,
    'normal',
    null,
    'inbox_message',
    source_id_text
  );
  return new;
end;
$$;

drop trigger if exists trg_hq_notify_inbox_message on public.inbox_messages;
create trigger trg_hq_notify_inbox_message
after insert on public.inbox_messages
for each row execute function public.hq_notify_inbox_message();

revoke all on function public.hq_notify_inbox_message() from public,anon,authenticated;
grant execute on function public.hq_notify_inbox_message() to service_role;
