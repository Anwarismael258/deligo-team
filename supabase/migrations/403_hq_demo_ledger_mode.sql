begin;

-- Demo values are explicitly separated from future live money.
alter table hq.financial_accounts
  add column if not exists environment text not null default 'LIVE'
    check (environment in ('DEMO','LIVE'));

alter table hq.financial_transactions
  add column if not exists environment text not null default 'LIVE'
    check (environment in ('DEMO','LIVE')),
  add column if not exists is_test_user boolean not null default false;

create index if not exists idx_hq_financial_transactions_environment
  on hq.financial_transactions(environment, occurred_at desc);

-- Demo money can never be selected as live available funds.
create or replace view hq.live_financial_transactions as
  select * from hq.financial_transactions where environment = 'LIVE';

create or replace view hq.demo_financial_transactions as
  select * from hq.financial_transactions where environment = 'DEMO';

commit;
