-- Entregas idempotentes dos comprovativos de microcrédito.
create table if not exists public.loan_application_deliveries (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.loan_applications(id) on delete cascade,
  packet_type text not null check (packet_type in ('submitted','confirmed')),
  recipient_type text not null check (recipient_type in ('client','company')),
  recipient_phone text not null,
  pdf_path text not null,
  status text not null default 'sending' check (status in ('sending','sent','failed')),
  whatsapp_message_id text,
  error_message text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique (application_id, packet_type, recipient_type, recipient_phone)
);
revoke all on public.loan_application_deliveries from anon;
grant select on public.loan_application_deliveries to authenticated;
grant all on public.loan_application_deliveries to service_role;
alter table public.loan_application_deliveries enable row level security;

drop policy if exists "loan delivery staff read" on public.loan_application_deliveries;
create policy "loan delivery staff read" on public.loan_application_deliveries
  for select to authenticated using (public.is_loan_staff());
