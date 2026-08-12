begin;

alter table mestre24.professional_profiles
  add column if not exists profile_photo_path text,
  add column if not exists province text,
  add column if not exists neighbourhood text,
  add column if not exists latitude numeric(9,6),
  add column if not exists longitude numeric(9,6),
  add column if not exists experience_years integer check (experience_years >= 0),
  add column if not exists indicative_price_mzn numeric(12,2) check (indicative_price_mzn is null or indicative_price_mzn >= 0),
  add column if not exists availability_status text not null default 'unavailable'
    check (availability_status in ('available', 'busy', 'unavailable', 'away'));

create table if not exists mestre24.services (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references mestre24.categories(id) on delete restrict,
  name text not null,
  slug text not null unique,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists mestre24.professional_services (
  professional_user_id uuid not null references mestre24.professional_profiles(user_id) on delete cascade,
  service_id uuid not null references mestre24.services(id) on delete restrict,
  indicative_price_mzn numeric(12,2) check (indicative_price_mzn is null or indicative_price_mzn >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (professional_user_id, service_id)
);
create table if not exists mestre24.favorites (
  client_user_id uuid not null references mestre24.profiles(user_id) on delete cascade,
  professional_user_id uuid not null references mestre24.professional_profiles(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (client_user_id, professional_user_id),
  check (client_user_id <> professional_user_id)
);
create table if not exists mestre24.request_events (
  id bigint generated always as identity primary key,
  service_request_id uuid not null references mestre24.service_requests(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  previous_status text,
  next_status text not null,
  note text,
  created_at timestamptz not null default now()
);
create table if not exists mestre24.settings (
  setting_key text primary key,
  setting_value jsonb not null,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into mestre24.settings(setting_key, setting_value) values
  ('subscription_monthly_mzn', '50'::jsonb),
  ('subscription_days', '30'::jsonb),
  ('portfolio_max_items', '10'::jsonb),
  ('expiry_notice_days', '3'::jsonb),
  ('new_professional_onboarding_enabled', 'true'::jsonb)
on conflict(setting_key) do nothing;

insert into mestre24.services(category_id, name, slug)
select id, name, slug from mestre24.categories where parent_id is not null
on conflict(slug) do update set category_id = excluded.category_id, name = excluded.name, active = true, updated_at = now();

alter table mestre24.service_requests
  add column if not exists service_id uuid references mestre24.services(id) on delete set null,
  add column if not exists desired_at timestamptz,
  add column if not exists observations text,
  add column if not exists accepted_at timestamptz,
  add column if not exists rejected_at timestamptz,
  add column if not exists started_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists reviewed_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists disputed_at timestamptz,
  add column if not exists cancellation_reason text,
  add column if not exists rejection_reason text;

do $$ declare constraint_name text; begin
  select conname into constraint_name from pg_constraint
  where conrelid = 'mestre24.service_requests'::regclass and contype = 'c'
    and pg_get_constraintdef(oid) like '%status%' limit 1;
  if constraint_name is not null then execute format('alter table mestre24.service_requests drop constraint %I', constraint_name); end if;
end $$;
alter table mestre24.service_requests add constraint mestre24_service_request_status_check
  check (status in ('open','contacted','requested','accepted','rejected','in_progress','completed','reviewed','cancelled','disputed'));

do $$ declare constraint_name text; begin
  select conname into constraint_name from pg_constraint
  where conrelid = 'mestre24.kyc_verifications'::regclass and contype = 'c'
    and pg_get_constraintdef(oid) like '%status%' limit 1;
  if constraint_name is not null then execute format('alter table mestre24.kyc_verifications drop constraint %I', constraint_name); end if;
end $$;
alter table mestre24.kyc_verifications add constraint mestre24_kyc_status_check
  check (status in ('not_submitted','pending','approved','rejected','requires_update','suspended'));

insert into storage.buckets(id, name, public)
values ('mestre24-kyc', 'mestre24-kyc', false)
on conflict(id) do update set public = false;
create policy mestre24_kyc_upload_own on storage.objects for insert to authenticated
  with check (bucket_id = 'mestre24-kyc' and (storage.foldername(name))[1] = auth.uid()::text);
create policy mestre24_kyc_read_own on storage.objects for select to authenticated
  using (bucket_id = 'mestre24-kyc' and (storage.foldername(name))[1] = auth.uid()::text);

create or replace function mestre24.transition_request(
  p_request_id uuid, p_next_status text, p_note text default null
) returns mestre24.service_requests
language plpgsql security definer set search_path = mestre24, public, pg_temp as $$
declare current_request mestre24.service_requests; v_previous_status text; v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'UNAUTHORIZED'; end if;
  select * into current_request from mestre24.service_requests where id = p_request_id for update;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  if p_next_status = 'cancelled' and current_request.client_user_id <> v_user_id then raise exception 'ONLY_CLIENT_CAN_CANCEL'; end if;
  if p_next_status in ('accepted','rejected','in_progress','completed') and current_request.professional_user_id <> v_user_id then raise exception 'ONLY_ASSIGNED_PROFESSIONAL_CAN_TRANSITION'; end if;
  if (current_request.status, p_next_status) not in (
    ('open','accepted'),('requested','accepted'),('contacted','accepted'),
    ('open','rejected'),('requested','rejected'),('contacted','rejected'),
    ('accepted','in_progress'),('in_progress','completed'),
    ('open','cancelled'),('requested','cancelled'),('accepted','cancelled'),('in_progress','disputed')
  ) then raise exception 'INVALID_REQUEST_TRANSITION'; end if;
  v_previous_status := current_request.status;
  update mestre24.service_requests set status = p_next_status, updated_at = now(),
    accepted_at = case when p_next_status='accepted' then now() else accepted_at end,
    rejected_at = case when p_next_status='rejected' then now() else rejected_at end,
    started_at = case when p_next_status='in_progress' then now() else started_at end,
    completed_at = case when p_next_status='completed' then now() else completed_at end,
    cancelled_at = case when p_next_status='cancelled' then now() else cancelled_at end,
    disputed_at = case when p_next_status='disputed' then now() else disputed_at end,
    cancellation_reason = case when p_next_status='cancelled' then p_note else cancellation_reason end,
    rejection_reason = case when p_next_status='rejected' then p_note else rejection_reason end
  where id = p_request_id returning * into current_request;
  insert into mestre24.request_events(service_request_id, actor_user_id, previous_status, next_status, note)
  values(p_request_id, v_user_id, v_previous_status, p_next_status, p_note);
  return current_request;
end;
$$;

create or replace function mestre24.submit_review(p_request_id uuid, p_rating smallint, p_comment text default null)
returns mestre24.reviews
language plpgsql security definer set search_path = mestre24, public, pg_temp as $$
declare request_row mestre24.service_requests; result mestre24.reviews;
begin
  if auth.uid() is null then raise exception 'UNAUTHORIZED'; end if;
  if p_rating not between 1 and 5 then raise exception 'INVALID_RATING'; end if;
  select * into request_row from mestre24.service_requests where id=p_request_id for update;
  if not found or request_row.client_user_id <> auth.uid() then raise exception 'REVIEW_NOT_ALLOWED'; end if;
  if request_row.status not in ('completed','reviewed') then raise exception 'REVIEW_REQUIRES_COMPLETED_SERVICE'; end if;
  insert into mestre24.reviews(service_request_id, reviewer_user_id, reviewed_user_id, rating, comment)
  values(p_request_id, auth.uid(), request_row.professional_user_id, p_rating, p_comment) returning * into result;
  update mestre24.professional_profiles pp set rating = stats.average_rating, review_count = stats.review_count, updated_at = now()
  from (select avg(rating)::numeric(3,2) average_rating, count(*)::integer review_count from mestre24.reviews where reviewed_user_id=request_row.professional_user_id) stats
  where pp.user_id=request_row.professional_user_id;
  update mestre24.service_requests set status='reviewed', reviewed_at=now(), updated_at=now() where id=p_request_id;
  return result;
end;
$$;

create or replace function mestre24.submit_kyc_document(p_document_type text, p_storage_path text)
returns mestre24.kyc_verifications
language plpgsql security definer set search_path = mestre24, public, pg_temp as $$
declare result mestre24.kyc_verifications;
begin
  if auth.uid() is null then raise exception 'UNAUTHORIZED'; end if;
  if p_document_type not in ('identity_document','selfie','professional_certificate','licence','other') then raise exception 'INVALID_DOCUMENT_TYPE'; end if;
  if p_storage_path !~ ('^' || auth.uid()::text || '/') then raise exception 'INVALID_KYC_STORAGE_PATH'; end if;
  if not exists(select 1 from mestre24.professional_profiles where user_id=auth.uid()) then raise exception 'PROFESSIONAL_PROFILE_REQUIRED'; end if;
  insert into mestre24.kyc_verifications(professional_user_id, document_type, storage_path, status)
  values(auth.uid(), p_document_type, p_storage_path, 'pending') returning * into result;
  update mestre24.professional_profiles set verification_status='pending', updated_at=now() where user_id=auth.uid();
  return result;
end;
$$;

create or replace function mestre24.submit_report(p_professional_user_id uuid, p_service_request_id uuid, p_reason text, p_details text default null)
returns mestre24.reports
language plpgsql security definer set search_path = mestre24, public, pg_temp as $$
declare result mestre24.reports;
begin
  if auth.uid() is null then raise exception 'UNAUTHORIZED'; end if;
  if coalesce(nullif(trim(p_reason), ''), '') = '' then raise exception 'REPORT_REASON_REQUIRED'; end if;
  if p_service_request_id is not null and not exists(select 1 from mestre24.service_requests where id=p_service_request_id and client_user_id=auth.uid() and professional_user_id=p_professional_user_id) then raise exception 'REPORT_REQUEST_NOT_ALLOWED'; end if;
  insert into mestre24.reports(reporter_user_id, professional_user_id, service_request_id, reason, details)
  values(auth.uid(), p_professional_user_id, p_service_request_id, p_reason, p_details) returning * into result;
  return result;
end;
$$;

create or replace function mestre24.expire_due_subscriptions()
returns integer language plpgsql security definer set search_path = mestre24, public, pg_temp as $$
declare expired_count integer;
begin
  with expired as (
    update mestre24.subscription_cycles set status='expired'
    where status in ('pending','paid','active') and expires_at <= now()
    returning professional_user_id, id
  ), updated as (
    update mestre24.professional_profiles pp set subscription_status='expired', visible_in_marketplace=false, updated_at=now()
    where pp.user_id in (select professional_user_id from expired) returning pp.user_id
  ), audited as (
    insert into mestre24.audit_events(actor_user_id, action, target_type, target_id, metadata)
    select null, 'subscription_expired', 'subscription_cycle', id, '{}'::jsonb from expired
  ) select count(*) into expired_count from updated;
  return expired_count;
end;
$$;

alter table mestre24.services enable row level security;
alter table mestre24.professional_services enable row level security;
alter table mestre24.favorites enable row level security;
alter table mestre24.request_events enable row level security;
alter table mestre24.settings enable row level security;
create policy mestre24_services_read on mestre24.services for select to authenticated using (active);
create policy mestre24_professional_services_self on mestre24.professional_services for all to authenticated using (professional_user_id=auth.uid()) with check (professional_user_id=auth.uid());
create policy mestre24_favorites_self on mestre24.favorites for all to authenticated using (client_user_id=auth.uid()) with check (client_user_id=auth.uid());
create policy mestre24_request_events_participant on mestre24.request_events for select to authenticated using (exists (select 1 from mestre24.service_requests r where r.id=service_request_id and (r.client_user_id=auth.uid() or r.professional_user_id=auth.uid())));
revoke all on mestre24.settings from anon, authenticated;
grant all on mestre24.services, mestre24.professional_services, mestre24.favorites, mestre24.request_events, mestre24.settings to service_role;
revoke all on function mestre24.transition_request(uuid,text,text), mestre24.submit_review(uuid,smallint,text), mestre24.submit_kyc_document(text,text), mestre24.submit_report(uuid,uuid,text,text), mestre24.expire_due_subscriptions() from public;
grant execute on function mestre24.transition_request(uuid,text,text), mestre24.submit_review(uuid,smallint,text), mestre24.submit_kyc_document(text,text), mestre24.submit_report(uuid,uuid,text,text) to authenticated;
grant execute on function mestre24.expire_due_subscriptions() to service_role;

create index if not exists mestre24_favorites_client_idx on mestre24.favorites(client_user_id, created_at desc);
create index if not exists mestre24_services_category_idx on mestre24.services(category_id, active);
create index if not exists mestre24_request_events_request_idx on mestre24.request_events(service_request_id, created_at desc);

commit;
