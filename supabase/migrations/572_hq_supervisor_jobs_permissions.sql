begin;

with grants(role_code, permission_code) as (
  values ('SUPERVISOR', 'news.view'), ('SUPERVISOR', 'news.create')
)
insert into hq.role_permissions(role_id, permission_id)
select r.id, p.id
from grants g
join hq.roles r on r.code = g.role_code
join hq.permissions p on p.code = g.permission_code
on conflict (role_id, permission_id) do update set effect = 'allow';

commit;
