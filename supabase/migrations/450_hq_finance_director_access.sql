begin;

-- Finance Director is the corporate finance role used by the co-CEO account.
-- Keep the same read/write finance scope as FINANCE without changing payout rules.
with grants(role_code, permission_code) as (values
  ('FINANCE_DIRECTOR','finance.view'),
  ('FINANCE_DIRECTOR','finance.createExpense'),
  ('FINANCE_DIRECTOR','finance.approvePayment'),
  ('FINANCE_DIRECTOR','support.viewTickets'),
  ('FINANCE_DIRECTOR','support.reply')
)
insert into hq.role_permissions(role_id, permission_id)
select r.id, p.id
from grants g
join hq.roles r on r.code = g.role_code and r.active
join hq.permissions p on p.code = g.permission_code
on conflict(role_id, permission_id) do update set effect = 'allow';

commit;
