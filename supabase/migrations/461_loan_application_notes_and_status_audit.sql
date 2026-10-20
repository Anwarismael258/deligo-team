-- Triunfal Microcrédito: notas internas e auditoria imutável do pedido.
create table if not exists public.loan_application_notes (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.loan_applications(id) on delete cascade,
  author_id uuid not null default auth.uid() references auth.users(id),
  body text not null check (length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

revoke all on public.loan_application_notes from anon;
grant select, insert on public.loan_application_notes to authenticated;
grant all on public.loan_application_notes to service_role;
alter table public.loan_application_notes enable row level security;

create or replace function public.is_loan_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_roles r
    where r.user_id = auth.uid() and r.role::text in ('admin','financas')
  )
$$;
grant execute on function public.is_loan_staff() to authenticated;

drop policy if exists "loan notes staff read" on public.loan_application_notes;
create policy "loan notes staff read" on public.loan_application_notes
  for select to authenticated using (public.is_loan_staff());
drop policy if exists "loan notes staff insert" on public.loan_application_notes;
create policy "loan notes staff insert" on public.loan_application_notes
  for insert to authenticated
  with check (public.is_loan_staff() and author_id = auth.uid());

alter table public.loan_applications
  add column if not exists status_updated_at timestamptz,
  add column if not exists status_updated_by uuid references auth.users(id);

create or replace function public.loan_status_audit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    new.status_updated_at := now();
    new.status_updated_by := auth.uid();
  end if;
  if (new.full_name, new.bi_number, new.nuit, new.phone, new.amount, new.total_due,
      new.bi_front_path, new.bi_back_path, new.income_path)
     is distinct from
     (old.full_name, old.bi_number, old.nuit, old.phone, old.amount, old.total_due,
      old.bi_front_path, old.bi_back_path, old.income_path) then
    raise exception 'dados do pedido nao podem ser alterados';
  end if;
  return new;
end $$;

drop trigger if exists loan_status_audit on public.loan_applications;
create trigger loan_status_audit before update on public.loan_applications
  for each row execute function public.loan_status_audit();
