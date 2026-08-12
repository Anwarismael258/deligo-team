begin;
create table if not exists core.hq_operational_alerts (
 id uuid primary key default gen_random_uuid(), platform text not null check(platform in ('deligo','sarca','taomoz')), alert_type text not null, severity text not null default 'warning' check(severity in ('info','warning','critical')), entity_id text not null, detected_at timestamptz not null default now(), resolved_at timestamptz, metadata jsonb not null default '{}'::jsonb
);
alter table core.hq_operational_alerts enable row level security;
revoke all on core.hq_operational_alerts from public, anon, authenticated;
grant all on core.hq_operational_alerts to service_role;
create unique index if not exists ux_hq_operational_alerts_open on core.hq_operational_alerts(platform,alert_type,entity_id) where resolved_at is null;
create index if not exists idx_hq_operational_alerts_open on core.hq_operational_alerts(platform,severity,detected_at desc) where resolved_at is null;
commit;
