create or replace function public.admin_complete_order(
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_order public.orders%rowtype;
begin
  v_role := auth.role();
  if v_role is null or v_role <> 'service_role' then
    raise exception 'not_authorized';
  end if;

  select *
    into v_order
    from public.orders
   where id = p_order_id
   for update;

  if not found then
    raise exception 'order_not_found';
  end if;

  update public.orders
     set status = 'completed',
         confirmed_by_customer = true,
         updated_at = now()
   where id = p_order_id
   returning * into v_order;

  return to_jsonb(v_order);
end;
$$;
revoke execute on function public.admin_complete_order(uuid) from public;
grant execute on function public.admin_complete_order(uuid) to service_role;
