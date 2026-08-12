do $$
declare
  v_anwar_id uuid;
begin
  select id
  into v_anwar_id
  from public.profiles
  where lower(coalesce(full_name, '')) like 'anwar%'
  order by created_at asc
  limit 1;

  if v_anwar_id is null then
    raise notice 'Conta do Anwar nao encontrada. Nada para apagar.';
    return;
  end if;

  delete from public.messages
  where order_id in (
    select id
    from public.orders
    where client_id = v_anwar_id
       or customer_id = v_anwar_id
  );

  delete from public.orders
  where client_id = v_anwar_id
     or customer_id = v_anwar_id;
end
$$;
