begin;

create table if not exists casadireta.support_cases (
  id uuid primary key default gen_random_uuid(),
  case_number text not null unique default ('CD-' || to_char(now(),'YYYY') || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
  requester_user_id uuid not null references auth.users(id) on delete cascade,
  requester_name text not null default '', requester_phone text not null default '',
  subject text not null check (char_length(btrim(subject)) between 3 and 160),
  description text not null check (char_length(btrim(description)) between 1 and 5000),
  category text not null default 'general', priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status text not null default 'open' check (status in ('open','in_progress','waiting_customer','resolved','closed')),
  assigned_employee_id uuid, metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists casadireta_support_cases_queue_idx on casadireta.support_cases(status, priority, updated_at desc);
create index if not exists casadireta_support_cases_requester_idx on casadireta.support_cases(requester_user_id, created_at desc);

create table if not exists casadireta.support_messages (
  id uuid primary key default gen_random_uuid(), case_id uuid not null references casadireta.support_cases(id) on delete cascade,
  author_type text not null check (author_type in ('customer','staff','system')),
  author_user_id uuid, author_name text not null default '', body text not null check (char_length(btrim(body)) between 1 and 10000),
  is_internal boolean not null default false, created_at timestamptz not null default now(), read_at timestamptz
);
create index if not exists casadireta_support_messages_case_idx on casadireta.support_messages(case_id, created_at);

alter table casadireta.support_cases enable row level security;
alter table casadireta.support_messages enable row level security;
drop policy if exists casadireta_support_cases_read on casadireta.support_cases;
create policy casadireta_support_cases_read on casadireta.support_cases for select to authenticated using (requester_user_id = auth.uid());
drop policy if exists casadireta_support_cases_insert on casadireta.support_cases;
create policy casadireta_support_cases_insert on casadireta.support_cases for insert to authenticated with check (requester_user_id = auth.uid());
drop policy if exists casadireta_support_cases_update on casadireta.support_cases;
create policy casadireta_support_cases_update on casadireta.support_cases for update to authenticated using (requester_user_id = auth.uid()) with check (requester_user_id = auth.uid());
drop policy if exists casadireta_support_messages_read on casadireta.support_messages;
create policy casadireta_support_messages_read on casadireta.support_messages for select to authenticated using (exists (select 1 from casadireta.support_cases c where c.id = case_id and c.requester_user_id = auth.uid()));
drop policy if exists casadireta_support_messages_insert on casadireta.support_messages;
create policy casadireta_support_messages_insert on casadireta.support_messages for insert to authenticated with check (author_type = 'customer' and author_user_id = auth.uid() and exists (select 1 from casadireta.support_cases c where c.id = case_id and c.requester_user_id = auth.uid()));
drop policy if exists casadireta_support_messages_update on casadireta.support_messages;
create policy casadireta_support_messages_update on casadireta.support_messages for update to authenticated using (exists (select 1 from casadireta.support_cases c where c.id = case_id and c.requester_user_id = auth.uid())) with check (exists (select 1 from casadireta.support_cases c where c.id = case_id and c.requester_user_id = auth.uid()));

create or replace function casadireta.touch_support_case() returns trigger language plpgsql security definer set search_path = casadireta, public as $$
begin
  update casadireta.support_cases set updated_at = new.created_at, status = case when new.author_type='customer' and status in ('resolved','closed') then 'open' when new.author_type='customer' then 'open' else 'in_progress' end where id = new.case_id;
  if new.author_type='staff' and not new.is_internal then
    insert into casadireta.notifications(user_id,type,title,body) select c.requester_user_id,'support_reply','Resposta da Central',left(new.body,240) from casadireta.support_cases c where c.id=new.case_id;
  end if;
  return new;
end $$;
drop trigger if exists casadireta_support_message_touch on casadireta.support_messages;
create trigger casadireta_support_message_touch after insert on casadireta.support_messages for each row execute function casadireta.touch_support_case();

revoke all on casadireta.support_cases, casadireta.support_messages from anon;
grant select, insert, update on casadireta.support_cases, casadireta.support_messages to authenticated;
grant all on casadireta.support_cases, casadireta.support_messages to service_role;

commit;
