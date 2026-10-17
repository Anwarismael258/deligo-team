begin;

-- Grant the unified HQ support queue to the named support stakeholders.
-- API-level checks still restrict Finance replies to financial cases.
with grants(role_code, permission_code) as (
  values
    ('SUPER_ADMIN','support.viewTickets'), ('SUPER_ADMIN','support.reply'), ('SUPER_ADMIN','support.close'),
    ('ADMIN','support.viewTickets'), ('ADMIN','support.reply'), ('ADMIN','support.close'),
    ('ADMINISTRATOR','support.viewTickets'), ('ADMINISTRATOR','support.reply'), ('ADMINISTRATOR','support.close'),
    ('SUPERVISOR','support.viewTickets'), ('SUPERVISOR','support.reply'), ('SUPERVISOR','support.close'),
    ('OPERATIONS_SUPERVISOR','support.viewTickets'), ('OPERATIONS_SUPERVISOR','support.reply'), ('OPERATIONS_SUPERVISOR','support.close'),
    ('CUSTOMER_SUPPORT','support.viewTickets'), ('CUSTOMER_SUPPORT','support.reply'), ('CUSTOMER_SUPPORT','support.close'),
    ('SUPPORT_AGENT','support.viewTickets'), ('SUPPORT_AGENT','support.reply'), ('SUPPORT_AGENT','support.close'),
    ('FINANCE','support.viewTickets'), ('FINANCE','support.reply'),
    ('FINANCE_DIRECTOR','support.viewTickets'), ('FINANCE_DIRECTOR','support.reply'),
    ('ACCOUNTANT','support.viewTickets'), ('ACCOUNTANT','support.reply')
)
insert into hq.role_permissions(role_id, permission_id, effect)
select r.id, p.id, 'allow'
from grants g
join hq.roles r on r.code = g.role_code and r.active
join hq.permissions p on p.code = g.permission_code
on conflict (role_id, permission_id) do update set effect = 'allow';

commit;
