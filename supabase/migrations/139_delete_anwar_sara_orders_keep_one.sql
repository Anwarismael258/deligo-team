do $$
declare
  v_client uuid;
  v_rest uuid;
  v_keep uuid;
  v_order_ids uuid[];
begin
  select id
    into v_client
    from public.profiles
   where phone in ('877688695', '+258877688695')
      or phone ilike '%877688695%'
   order by created_at asc
   limit 1;

  if v_client is null then
    raise notice 'Cliente Anwar nao encontrado. Nada para apagar.';
    return;
  end if;

  select id
    into v_rest
    from public.restaurants
   where lower(coalesce(name, '')) like '%sara%'
   order by created_at asc
   limit 1;

  if v_rest is null then
    raise notice 'Restaurante Sara nao encontrado. Nada para apagar.';
    return;
  end if;

  select id
    into v_keep
    from public.orders
   where restaurant_id = v_rest
     and (client_id = v_client or customer_id = v_client)
     and status in ('completed', 'delivered')
   order by created_at desc
   limit 1;

  if v_keep is null then
    select id
      into v_keep
      from public.orders
     where restaurant_id = v_rest
       and (client_id = v_client or customer_id = v_client)
     order by created_at desc
     limit 1;
  end if;

  if v_keep is null then
    raise notice 'Nenhum pedido encontrado para este cliente e restaurante.';
    return;
  end if;

  select array_agg(id)
    into v_order_ids
    from public.orders
   where restaurant_id = v_rest
     and (client_id = v_client or customer_id = v_client)
     and id <> v_keep;

  if v_order_ids is null then
    raise notice 'Nenhum pedido adicional para apagar. Mantido: %', v_keep;
    return;
  end if;

  if to_regclass('public.order_events') is not null then
    delete from public.order_events where order_id = any(v_order_ids);
  end if;
  if to_regclass('public.order_items') is not null then
    delete from public.order_items where order_id = any(v_order_ids);
  end if;
  if to_regclass('public.payment_splits') is not null then
    delete from public.payment_splits where order_id = any(v_order_ids);
  end if;
  if to_regclass('public.payments') is not null then
    delete from public.payments where order_id = any(v_order_ids);
  end if;
  if to_regclass('public.messages') is not null then
    delete from public.messages where order_id = any(v_order_ids);
  end if;
  if to_regclass('public.deliveries') is not null then
    delete from public.deliveries where order_id = any(v_order_ids);
  end if;
  if to_regclass('public.reviews') is not null then
    delete from public.reviews where order_id = any(v_order_ids);
  end if;
  if to_regclass('public.order_disputes') is not null then
    delete from public.order_disputes where order_id = any(v_order_ids);
  end if;

  delete from public.orders where id = any(v_order_ids);

  raise notice 'Pedidos apagados. Mantido: %', v_keep;
end
$$;
