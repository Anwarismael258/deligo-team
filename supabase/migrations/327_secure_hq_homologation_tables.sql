begin;
drop policy if exists core_hq_homologation_records_service_role_all
  on core.hq_homologation_records;
create policy core_hq_homologation_records_service_role_all
on core.hq_homologation_records
for all to service_role
using (true)
with check (true);
drop policy if exists core_hq_homologation_audit_service_role_all
  on core.hq_homologation_audit;
create policy core_hq_homologation_audit_service_role_all
on core.hq_homologation_audit
for all to service_role
using (true)
with check (true);
commit;
