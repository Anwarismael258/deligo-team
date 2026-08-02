begin;

create table if not exists hq.technology_credentials(
 id uuid primary key default gen_random_uuid(),legal_entity_id uuid not null references hq.legal_entities(id),system_id uuid references hq.technology_systems(id),integration_id uuid references hq.technology_integrations(id),
 name text not null,credential_type text not null,provider text,secret_reference text not null,status text not null default 'active' check(status in('active','rotating','revoked','expired')),
 last_rotated_at timestamptz,expires_at timestamptz,owner_employee_id uuid not null references hq.employees(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(secret_reference ~ '^(vault|supabase-vault|secret|env)://'),check(secret_reference not like '%BEGIN%'),check(position(E'\n' in secret_reference)=0)
);
create table if not exists hq.technology_domains(
 id uuid primary key default gen_random_uuid(),legal_entity_id uuid not null references hq.legal_entities(id),system_id uuid references hq.technology_systems(id),domain_name text not null unique,
 registrar text,dns_provider text,status text not null default 'active' check(status in('active','redirect','expired','suspended')),registered_on date,expires_on date,auto_renew boolean not null default false,
 owner_employee_id uuid not null references hq.employees(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists hq.technology_certificates(
 id uuid primary key default gen_random_uuid(),domain_id uuid references hq.technology_domains(id),system_id uuid references hq.technology_systems(id),common_name text not null,issuer text,
 serial_number_masked text,status text not null default 'valid' check(status in('valid','expiring','expired','revoked')),valid_from timestamptz,valid_until timestamptz not null,
 managed_by text,fingerprint_masked text,owner_employee_id uuid not null references hq.employees(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(fingerprint_masked is null or length(fingerprint_masked)<=32),check(serial_number_masked is null or length(serial_number_masked)<=32)
);
create table if not exists hq.technology_releases(
 id uuid primary key default gen_random_uuid(),legal_entity_id uuid not null references hq.legal_entities(id),platform_id uuid references hq.platforms(id),system_id uuid not null references hq.technology_systems(id),change_id uuid references hq.technology_changes(id),
 version text not null,environment text not null check(environment in('production','staging','development')),commit_reference text,status text not null default 'planned' check(status in('planned','deploying','succeeded','failed','rolled_back')),
 started_at timestamptz,completed_at timestamptz,deployed_by uuid references hq.employees(id),notes text,created_at timestamptz not null default now(),unique(system_id,environment,version)
);
create table if not exists hq.technology_failure_history(
 id uuid primary key default gen_random_uuid(),incident_id uuid not null references hq.technology_incidents(id) on delete cascade,system_id uuid references hq.technology_systems(id),
 event_type text not null check(event_type in('detected','investigation','status_change','mitigation','resolution','postmortem')),summary text not null,
 previous_status text,final_status text,created_by uuid not null references hq.employees(id),occurred_at timestamptz not null default now()
);

create or replace function hq.touch_technology_registry() returns trigger language plpgsql as $$ begin new.updated_at:=now();return new;end $$;
create or replace function hq.protect_technology_secret_reference() returns trigger language plpgsql security definer set search_path=hq,public as $$ begin if new.secret_reference is not null and (new.secret_reference !~ '^(vault|supabase-vault|secret|env)://' or new.secret_reference like '%BEGIN%' or position(E'\n' in new.secret_reference)>0) then raise exception 'Apenas referencia de cofre permitida';end if;return new;end $$;
drop trigger if exists trg_protect_integration_secret on hq.technology_integrations;create trigger trg_protect_integration_secret before insert or update of secret_reference on hq.technology_integrations for each row execute function hq.protect_technology_secret_reference();
drop trigger if exists trg_protect_credential_secret on hq.technology_credentials;create trigger trg_protect_credential_secret before insert or update of secret_reference on hq.technology_credentials for each row execute function hq.protect_technology_secret_reference();
drop trigger if exists trg_touch_technology_credentials on hq.technology_credentials;create trigger trg_touch_technology_credentials before update on hq.technology_credentials for each row execute function hq.touch_technology_registry();
drop trigger if exists trg_touch_technology_domains on hq.technology_domains;create trigger trg_touch_technology_domains before update on hq.technology_domains for each row execute function hq.touch_technology_registry();
drop trigger if exists trg_touch_technology_certificates on hq.technology_certificates;create trigger trg_touch_technology_certificates before update on hq.technology_certificates for each row execute function hq.touch_technology_registry();

do $$ declare t text;begin foreach t in array array['technology_credentials','technology_domains','technology_certificates','technology_releases','technology_failure_history'] loop execute format('alter table hq.%I enable row level security',t);execute format('revoke all on hq.%I from public,anon,authenticated',t);execute format('grant all on hq.%I to service_role',t);end loop;end $$;
create index if not exists idx_technology_credentials_expiry on hq.technology_credentials(status,expires_at);
create index if not exists idx_technology_domains_expiry on hq.technology_domains(status,expires_on);
create index if not exists idx_technology_certificates_expiry on hq.technology_certificates(status,valid_until);
create index if not exists idx_technology_releases_status on hq.technology_releases(environment,status,created_at desc);
create index if not exists idx_technology_failures_incident on hq.technology_failure_history(incident_id,occurred_at desc);

commit;
