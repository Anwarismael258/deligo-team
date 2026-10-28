begin;
create table hq.sms_marketing_consents (
 app_slug text not null, user_id uuid not null, phone text not null check(phone ~ '^2588[2-7][0-9]{7}$'),
 allowed boolean not null default false, evidence text not null check(length(evidence) between 5 and 1000),
 recorded_by uuid not null references hq.employees(id), updated_at timestamptz not null default now(),
 primary key(app_slug,user_id,phone)
);
create table hq.sms_suppressions (
 phone text primary key check(phone ~ '^2588[2-7][0-9]{7}$'), reason text not null,
 recorded_by uuid not null references hq.employees(id), created_at timestamptz not null default now()
);
create table hq.sms_campaigns (
 id uuid primary key default gen_random_uuid(), target_user_id uuid, app_slug text not null, title text not null check(length(title) between 3 and 120),
 message text not null check(length(message) between 1 and 1000), sender_id text not null,
 status text not null default 'draft' check(status in ('draft','ready','paused','cancelled','completed')),
 segments integer not null check(segments between 1 and 20), max_recipients integer not null check(max_recipients between 1 and 10000),
 created_by uuid not null references hq.employees(id), created_at timestamptz not null default now()
);
create table hq.sms_campaign_recipients (
 id uuid primary key default gen_random_uuid(), campaign_id uuid not null references hq.sms_campaigns(id),
 phone text not null, status text not null default 'queued' check(status in ('queued','sending','accepted','failed','unknown','cancelled')),
 provider_reference text, cost_mzn numeric, attempted_at timestamptz, finished_at timestamptz,
 unique(campaign_id,phone)
);
create index on hq.sms_campaign_recipients(campaign_id,status);
create table hq.sms_campaign_audit (
 id uuid primary key default gen_random_uuid(), campaign_id uuid references hq.sms_campaigns(id),
 actor_id uuid not null references hq.employees(id), action text not null, created_at timestamptz not null default now(), details jsonb not null default '{}'
);
do $$ declare t text; begin
 foreach t in array array['sms_marketing_consents','sms_suppressions','sms_campaigns','sms_campaign_recipients','sms_campaign_audit'] loop
 execute format('alter table hq.%I enable row level security',t);
 execute format('revoke all on hq.%I from public,anon,authenticated',t);
 execute format('grant select,insert,update on hq.%I to service_role',t);
 end loop;
end $$;
-- Credentials stay in the existing Vault, shared with OTP without modifying its hook.
create function public.hq_sms_provider_config_v1() returns jsonb
language sql security definer set search_path=pg_catalog,public as $$
 select jsonb_object_agg(name,decrypted_secret) from (
 select distinct on(name) name,decrypted_secret from vault.decrypted_secrets
 where name in ('mozesms_api_key','mozesms_api_secret','mozesms_sender_id') order by name,updated_at desc
 ) s
$$;
-- Snapshot eligibility atomically. No truncation and one SMS per normalized phone.
create function public.hq_sms_prepare_v1(p_id uuid,p_actor uuid) returns integer
language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare c hq.sms_campaigns; n integer;
begin
 select * into c from hq.sms_campaigns where id=p_id for update;
 if not found or c.status <> 'draft' then raise exception 'SMS_NOT_DRAFT'; end if;
 insert into hq.sms_campaign_recipients(campaign_id,phone)
 select c.id,s.phone from hq.sms_marketing_consents s
 where s.app_slug=c.app_slug and s.allowed and (c.target_user_id is null or s.user_id=c.target_user_id)
 and not exists(select 1 from hq.sms_suppressions x where x.phone=s.phone)
 and exists(select 1 from hq.global_user_platforms_v1 u where u.user_id=s.user_id and u.app_slug=s.app_slug
 and u.membership_status='active' and u.profile_status='active'
 and (case when length(regexp_replace(coalesce(u.primary_phone,''),'[^0-9]','','g'))=9 then '258' else '' end)||regexp_replace(coalesce(u.primary_phone,''),'[^0-9]','','g')=s.phone)
 group by s.phone;
 get diagnostics n=row_count;
 if n=0 then raise exception 'SMS_NO_ELIGIBLE_CONTACTS'; end if;
 if n>c.max_recipients then raise exception 'SMS_RECIPIENT_BUDGET_EXCEEDED'; end if;
 update hq.sms_campaigns set status='ready' where id=c.id;
 insert into hq.sms_campaign_audit(campaign_id,actor_id,action,details) values(c.id,p_actor,'prepared',jsonb_build_object('recipients',n,'segments',n*c.segments));
 return n;
end $$;
create function public.hq_sms_claim_v1(p_id uuid,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare c hq.sms_campaigns; r hq.sms_campaign_recipients;
begin
 -- Serialize all marketing claims; OTP uses its own existing path.
 perform pg_advisory_xact_lock(486,1);
 -- Expired in-flight messages become unknown, never requeued.
 select * into c from hq.sms_campaigns where id=p_id for update;
 if not found or c.status<>'ready' then return null; end if;
 update hq.sms_campaign_recipients set status='unknown',finished_at=now() where status='sending' and attempted_at<now()-interval '5 minutes';
 if exists(select 1 from hq.sms_campaign_recipients where status='sending') then return null; end if;
 update hq.sms_campaign_recipients r set status='cancelled',finished_at=now()
 where r.campaign_id=c.id and r.status='queued' and (
 exists(select 1 from hq.sms_suppressions x where x.phone=r.phone) or not exists(
 select 1 from hq.sms_marketing_consents s join hq.global_user_platforms_v1 u on u.user_id=s.user_id and u.app_slug=s.app_slug
 where s.app_slug=c.app_slug and s.phone=r.phone and s.allowed and u.membership_status='active' and u.profile_status='active'
 and (case when length(regexp_replace(coalesce(u.primary_phone,''),'[^0-9]','','g'))=9 then '258' else '' end)||regexp_replace(coalesce(u.primary_phone,''),'[^0-9]','','g')=s.phone));
 select * into r from hq.sms_campaign_recipients where campaign_id=c.id and status='queued' order by id limit 1 for update skip locked;
 if not found then
 update hq.sms_campaigns set status='completed' where id=c.id;
 return null;
 end if;
 update hq.sms_campaign_recipients set status='sending',attempted_at=now() where id=r.id;
 insert into hq.sms_campaign_audit(campaign_id,actor_id,action,details) values(c.id,p_actor,'claimed',jsonb_build_object('recipient_id',r.id));
 return jsonb_build_object('id',r.id,'phone',r.phone,'message',c.message,'sender',c.sender_id);
end $$;
create function public.hq_sms_control_v1(p_id uuid,p_actor uuid,p_action text) returns void
language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare c hq.sms_campaigns;
begin
 select * into c from hq.sms_campaigns where id=p_id for update;
 if not found then raise exception 'SMS_NOT_FOUND'; end if;
 if p_action='pause' and c.status='ready' then update hq.sms_campaigns set status='paused' where id=c.id;
 elsif p_action='resume' and c.status='paused' then update hq.sms_campaigns set status='ready' where id=c.id;
 elsif p_action='cancel' and c.status in ('draft','ready','paused') then
 update hq.sms_campaigns set status='cancelled' where id=c.id;
 update hq.sms_campaign_recipients set status='cancelled',finished_at=now() where campaign_id=c.id and status='queued';
 else raise exception 'SMS_INVALID_TRANSITION'; end if;
 insert into hq.sms_campaign_audit(campaign_id,actor_id,action) values(c.id,p_actor,p_action);
end $$;
create function public.hq_sms_stats_v1(p_id uuid) returns jsonb
language sql security definer set search_path=hq,public,pg_temp as $$
 select jsonb_build_object('counts',coalesce((select jsonb_object_agg(status,n) from (select status,count(*) n from hq.sms_campaign_recipients where campaign_id=p_id group by status) s),'{}'::jsonb),
 'recordedCost',coalesce((select sum(cost_mzn) from hq.sms_campaign_recipients where campaign_id=p_id),0))
$$;
revoke all on function public.hq_sms_stats_v1(uuid) from public,anon,authenticated;
grant execute on function public.hq_sms_stats_v1(uuid) to service_role;
revoke all on function public.hq_sms_provider_config_v1(),public.hq_sms_prepare_v1(uuid,uuid),public.hq_sms_claim_v1(uuid,uuid),public.hq_sms_control_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.hq_sms_provider_config_v1(),public.hq_sms_prepare_v1(uuid,uuid),public.hq_sms_claim_v1(uuid,uuid),public.hq_sms_control_v1(uuid,uuid,text) to service_role;
insert into hq.permissions(code,module,action,data_class,description) values
 ('marketing.sms','marketing','sms','personal','Gerir campanhas e consentimentos SMS nas plataformas atribuídas') on conflict(code) do nothing;
insert into hq.role_permissions(role_id,permission_id)
select r.id,p.id from hq.roles r cross join hq.permissions p where r.code in ('SUPER_ADMIN','MARKETING') and p.code='marketing.sms' on conflict(role_id,permission_id) do nothing;
notify pgrst,'reload schema';
commit;
