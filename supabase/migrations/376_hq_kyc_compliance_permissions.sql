begin;
insert into hq.role_permissions(role_id,permission_id)
select r.id,p.id from hq.roles r cross join hq.permissions p
where r.code='COMPLIANCE' and p.code in('field.view','field.approveKyc')
on conflict do nothing;
insert into hq.role_permissions(role_id,permission_id)
select r.id,p.id from hq.roles r cross join hq.permissions p
where r.code='LEGAL' and p.code='field.view'
on conflict do nothing;
commit;
