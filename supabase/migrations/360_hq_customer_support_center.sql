begin;

do $$ declare constraint_name text; begin
  select c.conname into constraint_name from pg_constraint c join pg_class r on r.oid=c.conrelid join pg_namespace n on n.oid=r.relnamespace
  where n.nspname='hq' and r.relname='support_tickets' and c.contype='c' and pg_get_constraintdef(c.oid) ilike '%status%' limit 1;
  if constraint_name is not null then execute format('alter table hq.support_tickets drop constraint %I',constraint_name); end if;
end $$;
update hq.support_tickets set status=case status when 'new' then 'open' when 'assigned' then 'in_analysis' when 'in_progress' then 'in_analysis' when 'waiting' then 'waiting_customer' else status end;
alter table hq.support_tickets
  add column if not exists ticket_type text not null default 'question' check(ticket_type in ('complaint','question','request','incident')),
  add column if not exists category text not null default 'general',
  add column if not exists description text,
  add column if not exists customer_name text,
  add column if not exists customer_contact text,
  add column if not exists assigned_by uuid references hq.employees(id),
  add column if not exists escalated_to uuid references hq.employees(id),
  add column if not exists escalated_at timestamptz,
  add column if not exists escalation_reason text,
  add column if not exists resolution text,
  add column if not exists closed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();
alter table hq.support_tickets add constraint support_tickets_status_check check(status in ('open','in_analysis','waiting_customer','escalated','resolved','closed'));
update hq.support_tickets set priority='normal' where priority not in ('low','normal','high','urgent') or priority is null;
alter table hq.support_tickets add constraint support_tickets_priority_check check(priority in ('low','normal','high','urgent'));

create table if not exists hq.support_conversations(
  id uuid primary key default gen_random_uuid(), ticket_id uuid not null references hq.support_tickets(id) on delete cascade,
  sender_type text not null check(sender_type in ('customer','agent','system')),
  sender_employee_id uuid references hq.employees(id), sender_customer_reference text,
  message text not null, is_internal boolean not null default false, created_at timestamptz not null default now()
);
create table if not exists hq.support_attachments(
  id uuid primary key default gen_random_uuid(), ticket_id uuid not null references hq.support_tickets(id) on delete cascade,
  conversation_id uuid references hq.support_conversations(id) on delete set null, file_name text not null, mime_type text,
  storage_reference text not null, uploaded_by uuid references hq.employees(id), created_at timestamptz not null default now()
);
create table if not exists hq.support_escalations(
  id uuid primary key default gen_random_uuid(), ticket_id uuid not null references hq.support_tickets(id) on delete cascade,
  from_employee_id uuid references hq.employees(id), to_employee_id uuid not null references hq.employees(id), reason text not null,
  status text not null default 'pending' check(status in ('pending','accepted','completed','cancelled')), created_at timestamptz not null default now(), completed_at timestamptz
);
create table if not exists hq.support_history(
  id uuid primary key default gen_random_uuid(), ticket_id uuid not null references hq.support_tickets(id) on delete cascade,
  event_type text not null, description text not null, actor_employee_id uuid references hq.employees(id),
  metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

create or replace function hq.enforce_support_ticket_transition() returns trigger language plpgsql security definer set search_path=hq,public as $$
begin
  if new.status<>old.status then
    if old.status='open' and new.status not in ('in_analysis','escalated','resolved') then raise exception 'Transicao de ticket invalida'; end if;
    if old.status='in_analysis' and new.status not in ('waiting_customer','escalated','resolved') then raise exception 'Transicao de ticket invalida'; end if;
    if old.status='waiting_customer' and new.status not in ('in_analysis','escalated','resolved') then raise exception 'Transicao de ticket invalida'; end if;
    if old.status='escalated' and new.status not in ('in_analysis','resolved') then raise exception 'Transicao de ticket invalida'; end if;
    if old.status='resolved' and new.status not in ('closed','in_analysis') then raise exception 'Transicao de ticket invalida'; end if;
    if old.status='closed' then raise exception 'Ticket encerrado'; end if;
    if new.status='resolved' then
      if coalesce(trim(new.resolution),'')='' then raise exception 'Resolucao obrigatoria'; end if;
      new.resolved_at:=now();
    elsif new.status='closed' then
      if old.status<>'resolved' or coalesce(trim(new.resolution),'')='' then raise exception 'Ticket precisa estar resolvido'; end if;
      new.closed_at:=now();
    elsif new.status='escalated' then
      if new.escalated_to is null or coalesce(trim(new.escalation_reason),'')='' then raise exception 'Destino e motivo do escalonamento obrigatorios'; end if;
      new.escalated_at:=now();
    end if;
  end if;
  new.updated_at:=now(); return new;
end $$;
drop trigger if exists trg_support_ticket_transition on hq.support_tickets;
create trigger trg_support_ticket_transition before update on hq.support_tickets for each row execute function hq.enforce_support_ticket_transition();

create index if not exists idx_support_ticket_queue on hq.support_tickets(status,priority,opened_at);
create index if not exists idx_support_conversation_ticket on hq.support_conversations(ticket_id,created_at);
create index if not exists idx_support_history_ticket on hq.support_history(ticket_id,created_at desc);
do $$ declare t text; begin foreach t in array array['support_conversations','support_attachments','support_escalations','support_history'] loop
  execute format('alter table hq.%I enable row level security',t);
  execute format('revoke all on hq.%I from public,anon,authenticated',t);
  execute format('grant all on hq.%I to service_role',t);
end loop; end $$;
revoke all on function hq.enforce_support_ticket_transition() from public,anon,authenticated;
grant execute on function hq.enforce_support_ticket_transition() to service_role;

commit;
