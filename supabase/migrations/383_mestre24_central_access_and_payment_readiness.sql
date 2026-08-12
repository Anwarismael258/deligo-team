begin;

-- Extend the existing central catalog without changing any existing platform.
do $$
declare constraint_name text;
begin
  select conname into constraint_name
  from pg_constraint
  where conrelid = 'core.apps'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) like '%module_schema%'
  limit 1;
  if constraint_name is not null then
    execute format('alter table core.apps drop constraint %I', constraint_name);
  end if;
end $$;
alter table core.apps add constraint core_apps_module_schema_check
  check (module_schema in ('deligo', 'comunhao', 'sarca', 'taomoz', 'mestre24'));

-- Payment provider values are only configuration readiness. No provider call,
-- payment initiation or settlement is enabled without official credentials.
do $$
declare constraint_name text;
begin
  select conname into constraint_name
  from pg_constraint
  where conrelid = 'payments.payment_methods'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) like '%method_type%'
  limit 1;
  if constraint_name is not null then
    execute format('alter table payments.payment_methods drop constraint %I', constraint_name);
  end if;
end $$;
alter table payments.payment_methods add constraint payments_payment_methods_method_type_check
  check (method_type in ('wallet', 'cash', 'mpesa', 'emola', 'movitel', 'card', 'bank', 'manual'));

do $$
declare constraint_name text;
begin
  select conname into constraint_name
  from pg_constraint
  where conrelid = 'mestre24.subscription_cycles'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) like '%provider%'
  limit 1;
  if constraint_name is not null then
    execute format('alter table mestre24.subscription_cycles drop constraint %I', constraint_name);
  end if;
end $$;
alter table mestre24.subscription_cycles add constraint mestre24_subscription_cycles_provider_check
  check (provider in ('mpesa', 'emola', 'movitel'));

do $$
declare constraint_name text;
begin
  select conname into constraint_name
  from pg_constraint
  where conrelid = 'mestre24.featured_promotions'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) like '%provider%'
  limit 1;
  if constraint_name is not null then
    execute format('alter table mestre24.featured_promotions drop constraint %I', constraint_name);
  end if;
end $$;
alter table mestre24.featured_promotions add constraint mestre24_featured_promotions_provider_check
  check (provider in ('mpesa', 'emola', 'movitel'));

grant usage on schema mestre24 to authenticated, service_role;

insert into core.apps (slug, name, display_name, description, runtime_type, module_schema, is_active, is_public)
values ('mestre24', 'Mestre24', 'Mestre24', 'Marketplace de profissionais e serviços.', 'mobile', 'mestre24', true, true)
on conflict (slug) do update set
  name = excluded.name, display_name = excluded.display_name,
  description = excluded.description, runtime_type = excluded.runtime_type,
  module_schema = excluded.module_schema, is_active = true, is_public = true,
  updated_at = now();

insert into core.roles (slug, name, scope, app_id, description)
select seed.slug, seed.name, 'app', app.id, seed.description
from (values
  ('mestre24_client', 'Cliente Mestre24', 'Pesquisa, pedidos, avaliações e denúncias.'),
  ('mestre24_professional', 'Profissional Mestre24', 'Perfil profissional, KYC, portfólio e subscrição.')
) as seed(slug, name, description)
join core.apps app on app.slug = 'mestre24'
on conflict (slug) do update set name = excluded.name, app_id = excluded.app_id,
  description = excluded.description, updated_at = now();

insert into hq.platforms (id, legal_entity_id, slug, name, schema_name)
values ('20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000001', 'mestre24', 'Mestre24', 'mestre24')
on conflict (slug) do update set name = excluded.name, schema_name = excluded.schema_name, status = 'active';

-- A user has one Conta Triunfal. This function only attaches an Mestre24 role
-- and creates the domain profile; it never creates a duplicate auth identity.
create or replace function mestre24.activate_my_role(
  p_role_slug text,
  p_full_name text,
  p_phone_e164 text
) returns table (role_slug text, profile_status text, trial_expires_at timestamptz)
language plpgsql security definer set search_path = mestre24, core, public, pg_temp as $$
declare
  v_user_id uuid := auth.uid();
  v_role_id uuid;
  v_app_id uuid;
  v_trial_expires_at timestamptz;
begin
  if v_user_id is null then raise exception 'UNAUTHORIZED'; end if;
  if p_role_slug not in ('mestre24_client', 'mestre24_professional') then
    raise exception 'INVALID_MESTRE24_ROLE';
  end if;
  if coalesce(nullif(trim(p_full_name), ''), '') = '' then raise exception 'FULL_NAME_REQUIRED'; end if;
  if p_phone_e164 !~ '^\+2588[2-7][0-9]{7}$' then raise exception 'INVALID_MOZAMBIQUE_PHONE'; end if;

  select r.id, r.app_id into v_role_id, v_app_id from core.roles r where r.slug = p_role_slug;
  if v_role_id is null then raise exception 'MESTRE24_ROLE_CATALOG_UNAVAILABLE'; end if;

  insert into core.profiles(user_id, primary_phone, full_name, display_name)
  values(v_user_id, p_phone_e164, p_full_name, p_full_name)
  on conflict(user_id) do update set primary_phone = excluded.primary_phone,
    full_name = coalesce(core.profiles.full_name, excluded.full_name), updated_at = now();
  insert into core.user_app_memberships(user_id, app_id, membership_status)
  values(v_user_id, v_app_id, 'active')
  on conflict(user_id, app_id) do update set membership_status = 'active', last_seen_at = now(), updated_at = now();
  insert into core.user_roles(user_id, role_id, assignment_reason)
  values(v_user_id, v_role_id, 'self_service_mestre24_onboarding')
  on conflict(user_id, role_id) do update set ends_at = null, updated_at = now();

  insert into mestre24.profiles(user_id, account_type, full_name, phone_e164)
  values(v_user_id, case when p_role_slug = 'mestre24_professional' then 'professional' else 'client' end, p_full_name, p_phone_e164)
  on conflict(user_id) do update set full_name = excluded.full_name, phone_e164 = excluded.phone_e164, updated_at = now();

  if p_role_slug = 'mestre24_professional' then
    insert into mestre24.professional_profiles(
      user_id, verification_status, subscription_status, visible_in_marketplace,
      trial_started_at, trial_expires_at
    ) values(v_user_id, 'pending', 'pending', false, now(), now() + interval '30 days')
    on conflict(user_id) do update set
      trial_started_at = coalesce(mestre24.professional_profiles.trial_started_at, excluded.trial_started_at),
      trial_expires_at = coalesce(mestre24.professional_profiles.trial_expires_at, excluded.trial_expires_at),
      updated_at = now()
    returning mestre24.professional_profiles.trial_expires_at into v_trial_expires_at;
  end if;
  return query select p_role_slug, 'active', v_trial_expires_at;
end;
$$;
revoke all on function mestre24.activate_my_role(text, text, text) from public;
grant execute on function mestre24.activate_my_role(text, text, text) to authenticated;

-- Only limited, approved and paid-or-trial professional fields are exposed to
-- signed-in search. Contact details remain private until an authorised flow is added.
create or replace function mestre24.search_active_professionals(
  p_query text default null,
  p_category_slug text default null,
  p_available_now boolean default false,
  p_neighbourhood text default null
) returns table (
  user_id uuid, full_name text, city text, district text, headline text,
  category_slug text, category_name text, rating numeric, review_count integer,
  available_now boolean, available_24h boolean, is_featured boolean
)
language sql stable security definer set search_path = mestre24, public, pg_temp as $$
  select ap.user_id, ap.full_name, ap.city, ap.district, ap.headline,
         c.slug, c.name, ap.rating, ap.review_count, ap.available_now,
         ap.available_24h, ap.is_featured
  from mestre24.active_professionals ap
  join mestre24.categories c on c.id = ap.category_id
  where (p_query is null or p_query = '' or ap.full_name ilike '%' || p_query || '%'
         or ap.headline ilike '%' || p_query || '%' or c.name ilike '%' || p_query || '%')
    and (p_category_slug is null or p_category_slug = '' or c.slug = p_category_slug
         or c.parent_id = (select id from mestre24.categories where slug = p_category_slug))
    and (not p_available_now or ap.available_now or ap.available_24h)
    and (p_neighbourhood is null or p_neighbourhood = '' or p_neighbourhood = any(ap.neighbourhoods))
  order by ap.is_featured desc, ap.available_now desc, ap.rating desc, ap.review_count desc;
$$;
revoke all on function mestre24.search_active_professionals(text, text, boolean, text) from public;
grant execute on function mestre24.search_active_professionals(text, text, boolean, text) to authenticated;

-- Default deny. The app uses narrowly scoped RPCs, while HQ service actions
-- remain governed by its existing service-role and corporate permissions.
alter table mestre24.profiles enable row level security;
alter table mestre24.professional_profiles enable row level security;
alter table mestre24.categories enable row level security;
alter table mestre24.subscription_cycles enable row level security;
alter table mestre24.service_requests enable row level security;
alter table mestre24.kyc_verifications enable row level security;
alter table mestre24.audit_events enable row level security;
alter table mestre24.portfolio_items enable row level security;
alter table mestre24.reviews enable row level security;
alter table mestre24.reports enable row level security;
alter table mestre24.featured_promotions enable row level security;
alter table mestre24.notifications enable row level security;

create policy mestre24_categories_read on mestre24.categories for select to authenticated using (active);
create policy mestre24_profiles_self on mestre24.profiles for select to authenticated using (user_id = auth.uid());
create policy mestre24_professional_profiles_self on mestre24.professional_profiles for select to authenticated using (user_id = auth.uid());
create policy mestre24_subscriptions_self on mestre24.subscription_cycles for select to authenticated using (professional_user_id = auth.uid());
create policy mestre24_kyc_self on mestre24.kyc_verifications for select to authenticated using (professional_user_id = auth.uid());
create policy mestre24_portfolio_self on mestre24.portfolio_items for all to authenticated using (professional_user_id = auth.uid()) with check (professional_user_id = auth.uid());
create policy mestre24_notifications_self on mestre24.notifications for select to authenticated using (user_id = auth.uid());
create policy mestre24_requests_participant on mestre24.service_requests for select to authenticated using (client_user_id = auth.uid() or professional_user_id = auth.uid());
create policy mestre24_requests_create_client on mestre24.service_requests for insert to authenticated with check (client_user_id = auth.uid());
create policy mestre24_reviews_participant on mestre24.reviews for select to authenticated using (reviewer_user_id = auth.uid() or reviewed_user_id = auth.uid());
create policy mestre24_reports_reporter on mestre24.reports for select to authenticated using (reporter_user_id = auth.uid());

commit;
