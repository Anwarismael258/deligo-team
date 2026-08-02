begin;

alter table hq.acquisition_leads add column if not exists organization_name text;
alter table hq.acquisition_leads add column if not exists lead_type text not null default 'business';
alter table hq.acquisition_leads add column if not exists email text;
alter table hq.acquisition_leads add column if not exists phone text;
alter table hq.acquisition_leads add column if not exists location text;
alter table hq.acquisition_leads add column if not exists source text;
alter table hq.acquisition_leads add column if not exists estimated_value numeric(18,2);
alter table hq.acquisition_leads add column if not exists notes text;
alter table hq.acquisition_leads add column if not exists updated_at timestamptz not null default now();

create table if not exists hq.acquisition_partners(
 id uuid primary key default gen_random_uuid(),legal_entity_id uuid not null references hq.legal_entities(id),platform_id uuid not null references hq.platforms(id),source_lead_id uuid unique references hq.acquisition_leads(id),
 partner_type text not null,legal_name text not null,display_name text,contact_name text,email text,phone text,location text,status text not null default 'onboarding' check(status in('onboarding','active','suspended','inactive')),
 agreement_reference text,onboarding_started_at timestamptz not null default now(),activated_at timestamptz,owner_id uuid references hq.employees(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table hq.acquisition_leads add column if not exists converted_partner_id uuid references hq.acquisition_partners(id);

create table if not exists hq.acquisition_visits(
 id uuid primary key default gen_random_uuid(),lead_id uuid not null references hq.acquisition_leads(id) on delete cascade,assigned_to uuid not null references hq.employees(id),visit_type text not null default 'commercial',
 objective text not null,scheduled_at timestamptz not null,location text,status text not null default 'scheduled' check(status in('scheduled','in_progress','completed','cancelled','no_show')),
 result text,completed_at timestamptz,created_by uuid not null references hq.employees(id),created_at timestamptz not null default now()
);
create table if not exists hq.acquisition_negotiations(
 id uuid primary key default gen_random_uuid(),lead_id uuid not null references hq.acquisition_leads(id) on delete cascade,owner_id uuid not null references hq.employees(id),proposal_reference text,
 proposed_value numeric(18,2) check(proposed_value is null or proposed_value>=0),terms_summary text,status text not null default 'draft' check(status in('draft','submitted','countered','accepted','rejected','expired')),
 valid_until date,decided_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists hq.acquisition_objectives(
 id uuid primary key default gen_random_uuid(),legal_entity_id uuid not null references hq.legal_entities(id),platform_id uuid references hq.platforms(id),owner_id uuid references hq.employees(id),
 period_start date not null,period_end date not null,target_leads integer not null default 0 check(target_leads>=0),target_visits integer not null default 0 check(target_visits>=0),target_conversions integer not null default 0 check(target_conversions>=0),
 target_value numeric(18,2) not null default 0 check(target_value>=0),created_by uuid not null references hq.employees(id),created_at timestamptz not null default now(),check(period_end>=period_start)
);
create table if not exists hq.acquisition_history(
 id uuid primary key default gen_random_uuid(),lead_id uuid not null references hq.acquisition_leads(id) on delete cascade,actor_employee_id uuid not null references hq.employees(id),event_type text not null,
 description text not null,previous_state jsonb,final_state jsonb,created_at timestamptz not null default now()
);

create or replace function hq.enforce_acquisition_lead_state() returns trigger language plpgsql security definer set search_path=hq,public as $$ begin
 if old.status='archived' and new.status<>old.status then raise exception 'Lead arquivado';end if;
 if new.status='converted' and new.converted_partner_id is null then raise exception 'Parceiro convertido obrigatorio';end if;
 if new.status='archived' and old.status not in('converted','lost') then raise exception 'Conclua o lead antes de arquivar';end if;
 new.updated_at:=now();return new;end $$;
drop trigger if exists trg_acquisition_lead_state on hq.acquisition_leads;create trigger trg_acquisition_lead_state before update on hq.acquisition_leads for each row execute function hq.enforce_acquisition_lead_state();

create or replace function public.hq_convert_acquisition_lead_v1(p_lead_id uuid,p_actor_employee_id uuid,p_partner_type text,p_agreement_reference text default null) returns jsonb language plpgsql security definer set search_path=hq,public as $$
declare l hq.acquisition_leads%rowtype;p hq.acquisition_partners%rowtype;
begin select * into l from hq.acquisition_leads where id=p_lead_id for update;if not found then raise exception 'Lead inexistente';end if;if l.status<>'open' or l.stage not in('qualified','visit_scheduled','negotiating','won') then raise exception 'Lead ainda nao qualificado';end if;
 insert into hq.acquisition_partners(legal_entity_id,platform_id,source_lead_id,partner_type,legal_name,display_name,contact_name,email,phone,location,agreement_reference,owner_id) values('10000000-0000-0000-0000-000000000001',l.platform_id,l.id,p_partner_type,coalesce(l.organization_name,l.name),l.organization_name,l.name,l.email,l.phone,l.location,p_agreement_reference,l.owner_id) returning * into p;
 update hq.acquisition_leads set stage='won',status='converted',converted_partner_id=p.id,updated_at=now() where id=l.id;
 insert into hq.acquisition_history(lead_id,actor_employee_id,event_type,description,previous_state,final_state) values(l.id,p_actor_employee_id,'converted','Lead convertido em parceiro',to_jsonb(l),jsonb_build_object('partner_id',p.id,'status','converted'));
 return jsonb_build_object('partner',to_jsonb(p),'lead_id',l.id);end $$;
revoke all on function public.hq_convert_acquisition_lead_v1(uuid,uuid,text,text) from public,anon,authenticated;grant execute on function public.hq_convert_acquisition_lead_v1(uuid,uuid,text,text) to service_role;

do $$ declare t text;begin foreach t in array array['acquisition_partners','acquisition_visits','acquisition_negotiations','acquisition_objectives','acquisition_history'] loop execute format('alter table hq.%I enable row level security',t);execute format('revoke all on hq.%I from public,anon,authenticated',t);execute format('grant all on hq.%I to service_role',t);end loop;end $$;
revoke all on hq.acquisition_leads from public,anon,authenticated;grant all on hq.acquisition_leads to service_role;
create index if not exists idx_acquisition_leads_pipeline on hq.acquisition_leads(platform_id,status,stage,next_follow_up_at);
create index if not exists idx_acquisition_visits_schedule on hq.acquisition_visits(status,scheduled_at);
create index if not exists idx_acquisition_negotiations_status on hq.acquisition_negotiations(status,valid_until);
create index if not exists idx_acquisition_history_lead on hq.acquisition_history(lead_id,created_at desc);
commit;
