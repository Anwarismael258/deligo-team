create or replace function public.log_order_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.order_events (
      order_id,
      event_type,
      old_status,
      new_status,
      metadata
    ) values (
      new.id,
      'order_created',
      null,
      new.status,
      jsonb_build_object(
        'payment_status', new.payment_status,
        'restaurant_id', new.restaurant_id,
        'courier_id', new.courier_id,
        'delivery_fee', new.delivery_fee
      )
    );
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if coalesce(old.status, '') is distinct from coalesce(new.status, '') then
      insert into public.order_events (
        order_id,
        event_type,
        old_status,
        new_status,
        metadata
      ) values (
        new.id,
        'status_changed',
        old.status,
        new.status,
        jsonb_build_object(
          'payment_status', new.payment_status,
          'courier_id', new.courier_id
        )
      );
    end if;

    if old.courier_id is distinct from new.courier_id then
      insert into public.order_events (
        order_id,
        event_type,
        old_status,
        new_status,
        metadata
      ) values (
        new.id,
        case
          when old.courier_id is null and new.courier_id is not null then 'courier_assigned'
          when old.courier_id is not null and new.courier_id is null then 'courier_unassigned'
          else 'courier_changed'
        end,
        old.status,
        new.status,
        jsonb_build_object(
          'old_courier_id', old.courier_id,
          'new_courier_id', new.courier_id
        )
      );
    end if;
  end if;

  return new;
end;
$$;
drop trigger if exists trg_log_order_event_insert on public.orders;
create trigger trg_log_order_event_insert
after insert on public.orders
for each row
execute function public.log_order_event();
drop trigger if exists trg_log_order_event_update on public.orders;
create trigger trg_log_order_event_update
after update on public.orders
for each row
execute function public.log_order_event();
