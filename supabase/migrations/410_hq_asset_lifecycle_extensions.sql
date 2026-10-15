begin;

-- Extensão aditiva do cadastro patrimonial: mantém o histórico e nunca apaga ativos.
alter table hq.assets add column if not exists acquisition_value numeric(18,2) check (acquisition_value is null or acquisition_value >= 0);
alter table hq.assets add column if not exists book_value numeric(18,2) check (book_value is null or book_value >= 0);
alter table hq.assets add column if not exists accumulated_depreciation numeric(18,2) not null default 0 check (accumulated_depreciation >= 0);
alter table hq.assets add column if not exists useful_life_months integer check (useful_life_months is null or useful_life_months > 0);
alter table hq.assets add column if not exists critical boolean not null default false;
alter table hq.assets add column if not exists qr_code text unique;
alter table hq.assets add column if not exists retired_reason text;
alter table hq.assets add column if not exists retired_at timestamptz;

create table if not exists hq.asset_inventory_checks(
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references hq.assets(id),
  inventory_name text not null,
  checked_at timestamptz not null default now(),
  result text not null check (result in ('found','missing','damaged','location_mismatch')),
  checked_by uuid references hq.employees(id),
  notes text
);
alter table hq.asset_inventory_checks enable row level security;
revoke all on hq.asset_inventory_checks from public,anon,authenticated;
grant all on hq.asset_inventory_checks to service_role;

commit;
