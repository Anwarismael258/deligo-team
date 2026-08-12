-- Mestre24: schema operacional. Aplicar no Supabase central antes de ativar registos reais.
create schema if not exists mestre24;

create table if not exists mestre24.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  account_type text not null check (account_type in ('client','professional')),
  full_name text not null,
  phone_e164 text not null unique,
  city text,
  district text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists mestre24.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists mestre24.professional_profiles (
  user_id uuid primary key references mestre24.profiles(user_id) on delete cascade,
  headline text,
  biography text,
  category_id uuid references mestre24.categories(id),
  verification_status text not null default 'pending' check (verification_status in ('pending','approved','rejected','suspended')),
  subscription_status text not null default 'pending' check (subscription_status in ('pending','paid','active','expired','suspended')),
  subscription_expires_at timestamptz,
  rating numeric(3,2) not null default 0,
  review_count integer not null default 0,
  visible_in_marketplace boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists mestre24.subscription_cycles (
  id uuid primary key default gen_random_uuid(),
  professional_user_id uuid not null references mestre24.professional_profiles(user_id) on delete restrict,
  amount numeric(12,2) not null default 50 check (amount = 50),
  currency text not null default 'MZN',
  status text not null default 'pending' check (status in ('pending','paid','active','expired','cancelled','failed')),
  provider text check (provider in ('mpesa','emola')),
  provider_reference text unique,
  starts_at timestamptz,
  expires_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists mestre24.service_requests (
  id uuid primary key default gen_random_uuid(),
  client_user_id uuid not null references mestre24.profiles(user_id) on delete restrict,
  professional_user_id uuid references mestre24.professional_profiles(user_id) on delete set null,
  category_id uuid references mestre24.categories(id),
  title text not null,
  description text not null,
  location_text text,
  status text not null default 'open' check (status in ('open','contacted','accepted','completed','cancelled','disputed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists mestre24.kyc_verifications (
  id uuid primary key default gen_random_uuid(),
  professional_user_id uuid not null references mestre24.professional_profiles(user_id) on delete cascade,
  document_type text not null,
  storage_path text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  reason text,
  created_at timestamptz not null default now()
);

create table if not exists mestre24.audit_events (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create index if not exists mestre24_professional_visible_idx on mestre24.professional_profiles(category_id, visible_in_marketplace, subscription_status, verification_status);
create index if not exists mestre24_requests_professional_idx on mestre24.service_requests(professional_user_id, status, created_at desc);

-- Só perfis aprovados e com subscrição activa podem aparecer na pesquisa pública.
create or replace view mestre24.active_professionals as
select p.user_id, p.full_name, p.city, p.district, pp.headline, pp.biography, pp.category_id, pp.rating, pp.review_count
from mestre24.profiles p
join mestre24.professional_profiles pp on pp.user_id = p.user_id
where p.active = true and pp.visible_in_marketplace = true and pp.verification_status = 'approved'
  and pp.subscription_status = 'active' and pp.subscription_expires_at > now();
