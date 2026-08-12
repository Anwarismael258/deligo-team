begin;

-- Private portfolio storage. Files are readable only by authenticated users
-- while the owning professional remains eligible for the marketplace.
insert into storage.buckets(id, name, public)
values ('mestre24-portfolio', 'mestre24-portfolio', false)
on conflict(id) do update set public = false;

create policy mestre24_portfolio_upload_own on storage.objects for insert to authenticated
  with check (
    bucket_id = 'mestre24-portfolio'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy mestre24_portfolio_read_own_or_active on storage.objects for select to authenticated
  using (
    bucket_id = 'mestre24-portfolio'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (
        select 1
        from mestre24.active_professionals active
        where active.user_id::text = (storage.foldername(name))[1]
      )
    )
  );
create policy mestre24_portfolio_delete_own on storage.objects for delete to authenticated
  using (
    bucket_id = 'mestre24-portfolio'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create or replace function mestre24.update_my_professional_profile(
  p_headline text default null,
  p_biography text default null,
  p_whatsapp_phone_e164 text default null,
  p_city text default null,
  p_district text default null,
  p_neighbourhood text default null,
  p_service_radius_km integer default null,
  p_available_now boolean default null,
  p_available_24h boolean default null,
  p_availability_status text default null,
  p_experience_years integer default null,
  p_indicative_price_mzn numeric default null
) returns mestre24.professional_profiles
language plpgsql security definer set search_path = mestre24, public, pg_temp as $$
declare result mestre24.professional_profiles;
begin
  if auth.uid() is null then raise exception 'UNAUTHORIZED'; end if;
  if p_whatsapp_phone_e164 is not null and p_whatsapp_phone_e164 !~ '^\\+2588[2-7][0-9]{7}$' then
    raise exception 'INVALID_MOZAMBIQUE_PHONE';
  end if;
  if p_service_radius_km is not null and p_service_radius_km not between 1 and 100 then
    raise exception 'INVALID_SERVICE_RADIUS';
  end if;
  if p_availability_status is not null and p_availability_status not in ('available','busy','unavailable','away') then
    raise exception 'INVALID_AVAILABILITY_STATUS';
  end if;
  update mestre24.profiles
    set city = coalesce(nullif(trim(p_city), ''), city),
        district = coalesce(nullif(trim(p_district), ''), district),
        updated_at = now()
    where user_id = auth.uid();
  update mestre24.professional_profiles
    set headline = coalesce(nullif(trim(p_headline), ''), headline),
        biography = coalesce(nullif(trim(p_biography), ''), biography),
        whatsapp_phone_e164 = coalesce(nullif(trim(p_whatsapp_phone_e164), ''), whatsapp_phone_e164),
        neighbourhood = coalesce(nullif(trim(p_neighbourhood), ''), neighbourhood),
        service_radius_km = coalesce(p_service_radius_km, service_radius_km),
        available_now = coalesce(p_available_now, available_now),
        available_24h = coalesce(p_available_24h, available_24h),
        availability_status = coalesce(p_availability_status, availability_status),
        experience_years = coalesce(p_experience_years, experience_years),
        indicative_price_mzn = coalesce(p_indicative_price_mzn, indicative_price_mzn),
        updated_at = now()
    where user_id = auth.uid()
    returning * into result;
  if not found then raise exception 'PROFESSIONAL_PROFILE_REQUIRED'; end if;
  insert into mestre24.audit_events(actor_user_id, action, target_type, target_id)
  values (auth.uid(), 'professional_profile_updated', 'professional_profile', auth.uid());
  return result;
end;
$$;

create or replace function mestre24.add_my_portfolio_item(
  p_storage_path text,
  p_caption text default null,
  p_work_stage text default 'after'
) returns mestre24.portfolio_items
language plpgsql security definer set search_path = mestre24, public, pg_temp as $$
declare result mestre24.portfolio_items;
begin
  if auth.uid() is null then raise exception 'UNAUTHORIZED'; end if;
  if p_work_stage not in ('before','after','other') then raise exception 'INVALID_PORTFOLIO_STAGE'; end if;
  if p_storage_path !~ ('^' || auth.uid()::text || '/portfolio/') then
    raise exception 'INVALID_PORTFOLIO_STORAGE_PATH';
  end if;
  insert into mestre24.portfolio_items(professional_user_id, storage_path, caption, work_stage, display_order)
  values (
    auth.uid(), p_storage_path, nullif(trim(p_caption), ''), p_work_stage,
    coalesce((select max(display_order) + 1 from mestre24.portfolio_items where professional_user_id = auth.uid()), 0)
  ) returning * into result;
  insert into mestre24.audit_events(actor_user_id, action, target_type, target_id)
  values (auth.uid(), 'portfolio_item_added', 'portfolio_item', result.id);
  return result;
end;
$$;

revoke all on function mestre24.update_my_professional_profile(text,text,text,text,text,text,integer,boolean,boolean,text,integer,numeric) from public;
revoke all on function mestre24.add_my_portfolio_item(text,text,text) from public;
grant execute on function mestre24.update_my_professional_profile(text,text,text,text,text,text,integer,boolean,boolean,text,integer,numeric) to authenticated;
grant execute on function mestre24.add_my_portfolio_item(text,text,text) to authenticated;

commit;
