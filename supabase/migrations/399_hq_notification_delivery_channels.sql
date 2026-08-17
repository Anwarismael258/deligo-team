-- Notification delivery orchestration. Providers remain configurable; no secret is stored here.
create table if not exists hq.notification_preferences (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references hq.employees(id) on delete cascade,
  in_app_enabled boolean not null default true, push_enabled boolean not null default true,
  sms_enabled boolean not null default true, email_enabled boolean not null default true,
  urgent_sms_enabled boolean not null default true, updated_at timestamptz not null default now(), unique(employee_id)
);
create table if not exists hq.notification_deliveries (
  id uuid primary key default gen_random_uuid(), notification_id uuid references hq.notifications(id) on delete cascade,
  employee_id uuid not null references hq.employees(id) on delete cascade,
  channel text not null check (channel in ('push','sms','email')),
  provider text not null check (provider in ('moz_esms','web_push','smtp')),
  destination_masked text, template_code text not null, payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','queued','sending','sent','delivered','failed','cancelled')),
  attempts integer not null default 0, provider_reference text, last_error text,
  next_attempt_at timestamptz not null default now(), sent_at timestamptz, delivered_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists hq_notification_delivery_once on hq.notification_deliveries(notification_id,channel) where status <> 'cancelled';
create index if not exists hq_notification_delivery_queue on hq.notification_deliveries(status,next_attempt_at) where status in ('pending','failed');
alter table hq.notification_preferences enable row level security;
alter table hq.notification_deliveries enable row level security;
grant select, insert, update on hq.notification_preferences, hq.notification_deliveries to service_role;
comment on table hq.notification_deliveries is 'Outbox for push, MozESMS SMS fallback and email; workers process this queue with retry and audit.';
notify pgrst, 'reload schema';
