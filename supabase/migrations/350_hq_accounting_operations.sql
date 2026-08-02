begin;

create unique index if not exists uq_hq_journal_source on hq.journal_entries(source_type,source_id) where source_type is not null and source_id is not null;

create table if not exists hq.accounting_invoices(
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id), platform_id uuid references hq.platforms(id),
  invoice_number text not null, direction text not null check(direction in('payable','receivable')), counterparty text not null,
  issued_on date not null, due_on date, subtotal numeric(18,2) not null default 0, tax_amount numeric(18,2) not null default 0,
  total_amount numeric(18,2) generated always as(subtotal+tax_amount) stored, currency text not null default 'MZN',
  status text not null default 'draft' check(status in('draft','issued','partially_paid','paid','overdue','cancelled')), document_path text,
  financial_transaction_id uuid references hq.financial_transactions(id), created_by uuid references hq.employees(id), created_at timestamptz not null default now(),
  unique(legal_entity_id,invoice_number)
);
create table if not exists hq.tax_obligations(
  id uuid primary key default gen_random_uuid(), legal_entity_id uuid not null references hq.legal_entities(id), tax_type text not null,
  period_start date not null, period_end date not null, due_on date not null, taxable_amount numeric(18,2) not null default 0,
  tax_amount numeric(18,2) not null default 0, status text not null default 'draft' check(status in('draft','prepared','approved','submitted','paid','overdue')),
  submission_reference text, document_path text, prepared_by uuid references hq.employees(id), approved_by uuid references hq.employees(id), created_at timestamptz not null default now()
);
alter table hq.accounting_invoices enable row level security; alter table hq.tax_obligations enable row level security;
revoke all on hq.accounting_invoices,hq.tax_obligations from public,anon,authenticated;
grant all on hq.accounting_invoices,hq.tax_obligations to service_role;

create or replace function hq.auto_post_finance_to_accounting() returns trigger language plpgsql security definer set search_path=hq,public as $$
declare entry_id uuid; cash_id uuid; counter_id uuid; src text; descr text; amt numeric; tx_type text; event_date date; creator uuid; approver uuid;
begin
  if tg_table_name='financial_transactions' then
    if new.status not in('posted','reconciled') or new.transaction_type not in('income','expense') then return new; end if;
    src:='financial_transaction'; descr:=coalesce(new.description,new.classification,'Operação financeira'); amt:=new.amount; tx_type:=new.transaction_type; event_date:=new.occurred_at::date; creator:=new.created_by; approver:=new.approved_by;
  else
    if new.status<>'paid' then return new; end if;
    src:='payment_request'; descr:=new.description; amt:=new.amount; tx_type:='expense'; event_date:=coalesce(new.paid_at::date,current_date); creator:=new.requested_by; approver:=new.approved_by;
  end if;
  if exists(select 1 from hq.journal_entries where source_type=src and source_id=new.id::text) then return new; end if;
  select id into cash_id from hq.chart_of_accounts where legal_entity_id=new.legal_entity_id and code='11';
  select id into counter_id from hq.chart_of_accounts where legal_entity_id=new.legal_entity_id and code=case when tx_type='income' then '41' else '51' end;
  insert into hq.journal_entries(legal_entity_id,platform_id,entry_date,description,source_type,source_id,status,created_by,posted_by,posted_at)
  values(new.legal_entity_id,new.platform_id,event_date,descr,src,new.id::text,'posted',creator,coalesce(approver,creator),now()) returning id into entry_id;
  if tx_type='income' then insert into hq.journal_lines(journal_entry_id,account_id,debit,credit) values(entry_id,cash_id,amt,0),(entry_id,counter_id,0,amt);
  else insert into hq.journal_lines(journal_entry_id,account_id,debit,credit) values(entry_id,counter_id,amt,0),(entry_id,cash_id,0,amt); end if;
  return new;
end $$;
drop trigger if exists trg_hq_finance_accounting on hq.financial_transactions;
create trigger trg_hq_finance_accounting after insert or update of status on hq.financial_transactions for each row execute function hq.auto_post_finance_to_accounting();
drop trigger if exists trg_hq_payment_accounting on hq.payment_requests;
create trigger trg_hq_payment_accounting after insert or update of status on hq.payment_requests for each row execute function hq.auto_post_finance_to_accounting();
revoke all on function hq.auto_post_finance_to_accounting() from public,anon,authenticated;
grant all on all sequences in schema hq to service_role;
commit;
