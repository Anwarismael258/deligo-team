begin;

-- Toda notificação criada pela regra de permissões gera um único sinal no feed
-- realtime. A Central usa este feed para atualizar a inbox sem refresh manual.
create or replace function hq.capture_notification_realtime() returns trigger
language plpgsql security definer set search_path=hq,public,pg_temp as $$
begin
  if not exists (
    select 1 from hq.realtime_events e
    where e.topic='notifications'
      and e.resource_type=coalesce(new.source_type,'notification')
      and e.resource_id=coalesce(new.source_id,new.id::text)
      and e.event_type='notification_created'
  ) then
    insert into hq.realtime_events(
      platform_id,department_id,topic,resource_type,resource_id,event_type,payload
    ) values (
      new.platform_id,
      new.origin_department_id,
      'notifications',
      coalesce(new.source_type,'notification'),
      coalesce(new.source_id,new.id::text),
      'notification_created',
      jsonb_build_object(
        'notification_id',new.id,
        'type',new.type,
        'category',new.category,
        'priority',new.priority,
        'action_required',new.action_required,
        'created_at',new.created_at
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_hq_notification_realtime on hq.notifications;
create trigger trg_hq_notification_realtime
after insert on hq.notifications
for each row execute function hq.capture_notification_realtime();

notify pgrst, 'reload schema';
commit;
