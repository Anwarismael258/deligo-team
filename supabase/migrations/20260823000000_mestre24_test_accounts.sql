-- Mestre24: seed administrativo de contas de teste unificadas.
-- Executar apenas no Supabase staging, com acesso administrativo.
-- Não cria auth.users, não contorna OTP e não confirma pagamentos.
do $$
declare
  u record;
begin
  for u in
    select id, phone, case phone
      when '+258841130015' then 'client'
      else 'professional'
    end as account_type,
    case phone
      when '+258841130015' then 'Mestre24 Cliente Teste'
      when '+258827688695' then 'Mestre24 Profissional Teste 1'
      when '+258877688695' then 'Mestre24 Profissional Teste 2'
    end as full_name
    from auth.users
    where phone in ('+258841130015', '+258827688695', '+258877688695')
  loop
    insert into mestre24.profiles (user_id, account_type, full_name, phone_e164, active)
    values (u.id, u.account_type, u.full_name, u.phone, true)
    on conflict (user_id) do update set
      account_type = excluded.account_type,
      phone_e164 = excluded.phone_e164,
      updated_at = now();

    if u.account_type = 'professional' then
      insert into mestre24.professional_profiles
        (user_id, headline, verification_status, subscription_status, visible_in_marketplace)
      values (u.id, case u.phone
        when '+258827688695' then 'Serviços gerais e manutenção residencial'
        else 'Transporte, entregas e logística'
      end, 'pending', 'pending', false)
      on conflict (user_id) do update set
        verification_status = 'pending',
        subscription_status = 'pending',
        visible_in_marketplace = false,
        updated_at = now();

      insert into mestre24.subscription_cycles
        (professional_user_id, amount, currency, status)
      select u.id, 50, 'MZN', 'pending'
      where not exists (
        select 1 from mestre24.subscription_cycles sc
        where sc.professional_user_id = u.id and sc.status = 'pending'
      );
    end if;
  end loop;
end $$;
