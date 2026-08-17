-- Executive finance: segregation of employee compensation, shareholder distributions
-- and dual control for corporate/profit-reserve movements.
alter table hq.logical_wallets add column if not exists owner_role text;
alter table hq.ledger_operations add column if not exists economic_category text;
alter table hq.ledger_operations add column if not exists approval_required integer not null default 1;
alter table hq.ledger_operations add column if not exists approval_count integer not null default 0;
alter table hq.ledger_operations add column if not exists second_approved_by uuid;
alter table hq.approval_matrix add column if not exists description text;

alter table hq.ledger_operations drop constraint if exists ledger_operations_economic_category_check;
alter table hq.ledger_operations add constraint ledger_operations_economic_category_check
  check (economic_category is null or economic_category in
    ('SALARY','BONUS','REIMBURSEMENT','ADVANCE','SHAREHOLDER_DISTRIBUTION','EXPENSE','SETTLEMENT','REFUND','INTERNAL_TRANSFER','REVENUE'));

insert into hq.logical_wallets(wallet_code, wallet_type, owner_role, currency, metadata)
values
  ('PROFIT_RESERVE_MZN','reserve','CORPORATE_EXECUTIVE','MZN','{"purpose":"retained corporate profit; distribution requires dual approval"}'::jsonb),
  ('SHAREHOLDER_CEO_MZN','shareholder','SUPER_ADMIN','MZN','{"purpose":"shareholder distributions only; not salary"}'::jsonb),
  ('SHAREHOLDER_FINANCE_DIRECTOR_MZN','shareholder','FINANCE_DIRECTOR','MZN','{"purpose":"shareholder distributions only; not salary"}'::jsonb),
  ('EMPLOYEE_CEO_MZN','employee','SUPER_ADMIN','MZN','{"purpose":"salary, bonus and reimbursement only"}'::jsonb),
  ('EMPLOYEE_FINANCE_DIRECTOR_MZN','employee','FINANCE_DIRECTOR','MZN','{"purpose":"salary, bonus and reimbursement only"}'::jsonb)
on conflict (wallet_code) do update set owner_role=excluded.owner_role, metadata=excluded.metadata;

insert into hq.approval_matrix(operation_type, minimum_amount, maximum_amount, required_approvers, required_roles, description)
values
  ('SHAREHOLDER_DISTRIBUTION',0,null,2,array['SUPER_ADMIN','FINANCE_DIRECTOR'],'Distribuição societária: aprovação dupla'),
  ('INTERNAL_TRANSFER',0,null,2,array['SUPER_ADMIN','FINANCE_DIRECTOR'],'Movimento envolvendo Corporate Wallet/Profit Reserve'),
  ('EXPENSE_PAYMENT',100000.01,null,2,array['FINANCE_DIRECTOR','SUPER_ADMIN'],'Despesa elevada: Financeiro + CEO'),
  ('EMPLOYEE_WITHDRAWAL',0,null,1,array['FINANCE_DIRECTOR'],'Levantamento de colaborador por categoria económica')
on conflict do nothing;

create or replace view hq.executive_finance_dashboard_v1 as
select
  coalesce(sum(case when wallet_type='corporate' then available_amount else 0 end),0) as corporate_wallet,
  coalesce(sum(case when wallet_type='reserve' then available_amount else 0 end),0) as profit_reserve,
  coalesce(sum(case when wallet_type='payroll' then reserved_amount else 0 end),0) as payroll_reserved,
  coalesce(sum(case when wallet_type='expense' then available_amount else 0 end),0) as expense_budget,
  coalesce(sum(case when wallet_type='settlement' then reserved_amount else 0 end),0) as settlement_payable
from hq.logical_wallets
where currency='MZN' and status='active';

comment on view hq.executive_finance_dashboard_v1 is 'Read-only executive view for CEO/Super Admin and Finance Director; never a payout endpoint.';
comment on column hq.ledger_operations.economic_category is 'Required for person-bound payouts; distinguishes salary, reimbursement, advance and shareholder distribution.';
comment on column hq.ledger_operations.approval_required is 'Resolved from configurable approval matrix, never hardcoded in UI.';

notify pgrst, 'reload schema';
