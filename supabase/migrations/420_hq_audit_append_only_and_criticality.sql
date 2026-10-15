begin;
alter table hq.audit_logs
  add column if not exists criticality text not null default 'normal',
  add column if not exists sensitivity text not null default 'internal',
  add column if not exists event_version integer not null default 1;
alter table hq.audit_logs drop constraint if exists audit_logs_criticality_check;
alter table hq.audit_logs add constraint audit_logs_criticality_check check(criticality in ('low','normal','high','critical'));
alter table hq.audit_logs drop constraint if exists audit_logs_sensitivity_check;
alter table hq.audit_logs add constraint audit_logs_sensitivity_check check(sensitivity in ('internal','confidential','restricted'));
create or replace function hq.prevent_audit_mutation() returns trigger language plpgsql security definer set search_path=hq,public as $$
begin
  raise exception 'audit_logs is append-only';
end $$;
drop trigger if exists trg_hq_audit_append_only on hq.audit_logs;
create trigger trg_hq_audit_append_only before update or delete on hq.audit_logs for each row execute function hq.prevent_audit_mutation();
create index if not exists idx_hq_audit_criticality on hq.audit_logs(criticality,occurred_at desc);
commit;
