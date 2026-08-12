begin;
alter table core.migration_constraint_issues enable row level security;
alter table core.migration_programmability_issues enable row level security;
do $$
declare
  target regclass;
  policy_name text;
begin
  foreach target in array array[
    'core.migration_constraint_issues'::regclass,
    'core.migration_programmability_issues'::regclass,
    'comunhao.asset_movements'::regclass,
    'comunhao.church_projects'::regclass,
    'comunhao.daily_devotional_library'::regclass,
    'comunhao.phone_auth_otps'::regclass,
    'comunhao.pilot_daily_snapshots'::regclass,
    'comunhao.scripture_reference_library'::regclass,
    'comunhao.task_checklist_items'::regclass,
    'comunhao.task_comments'::regclass,
    'core.field_visit_events'::regclass,
    'core.field_workers'::regclass,
    'core.hq_integration_credentials'::regclass,
    'core.marketing_campaign_apps'::regclass,
    'core.marketing_deliveries'::regclass,
    'core.staff_app_scopes'::regclass,
    'core.staff_profiles'::regclass,
    'core.support_case_events'::regclass,
    'payments.idempotency_keys'::regclass,
    'taomoz.commission_rules'::regclass,
    'taomoz.legacy_import_batches'::regclass,
    'taomoz.logistics_assignments'::regclass
  ]
  loop
    policy_name := replace(target::text, '.', '_') || '_service_role_all';
    if not exists (
      select 1 from pg_policies
      where schemaname = split_part(target::text, '.', 1)
        and tablename = split_part(target::text, '.', 2)
        and policyname = policy_name
    ) then
      execute format(
        'create policy %I on %s for all to service_role using (true) with check (true)',
        policy_name,
        target
      );
    end if;
  end loop;
end;
$$;
commit;
