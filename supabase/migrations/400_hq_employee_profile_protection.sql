-- Employee self-service profile is separate from the official HR employee record.
create table if not exists hq.employee_display_profiles (
  employee_id uuid primary key references hq.employees(id) on delete cascade,
  avatar_url text, biography text, personal_phone text, alternate_contact text,
  wallet_provider text check (wallet_provider is null or wallet_provider in ('vodacom_mpesa','movitel')),
  wallet_number_masked text, account_preferences jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists hq.employee_wallet_change_requests (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references hq.employees(id) on delete cascade,
  provider text not null check (provider in ('vodacom_mpesa','movitel')), old_number_masked text, new_number_masked text not null,
  new_number_hash text not null, status text not null default 'otp_pending' check (status in ('otp_pending','approved','rejected','expired')),
  requested_at timestamptz not null default now(), wallet_number_changed_at timestamptz,
  confirmed_at timestamptz, confirmed_by uuid references hq.employees(id) on delete set null,
  ip_address inet, device_reference text, failure_reason text
);
create table if not exists hq.employee_wallet_change_history (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references hq.employees(id) on delete cascade,
  old_number_masked text, new_number_masked text not null, provider text not null,
  wallet_number_changed_at timestamptz not null default now(), operator uuid references hq.employees(id) on delete set null,
  changed_by uuid references hq.employees(id) on delete set null, ip_address inet, device_reference text, request_id uuid references hq.employee_wallet_change_requests(id)
);
alter table hq.employee_display_profiles enable row level security;
alter table hq.employee_wallet_change_requests enable row level security;
alter table hq.employee_wallet_change_history enable row level security;
grant select, insert, update on hq.employee_display_profiles, hq.employee_wallet_change_requests, hq.employee_wallet_change_history to service_role;
comment on table hq.employee_display_profiles is 'Self-service fields only; never used as official HR identity or payroll source.';
comment on table hq.employee_wallet_change_requests is 'Wallet changes require current-password/OTP policy before approval.';
comment on table hq.employee_wallet_change_history is 'Immutable audit trail for wallet destination changes.';
notify pgrst, 'reload schema';
