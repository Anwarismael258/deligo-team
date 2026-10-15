begin;

create table if not exists hq.ai_tool_registry (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text not null,
  action_level text not null check (action_level in ('read','prepare','execute')),
  data_class text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists hq.ai_role_tools (
  role_id uuid not null references hq.roles(id),
  tool_id uuid not null references hq.ai_tool_registry(id),
  platform_id uuid references hq.platforms(id),
  allowed boolean not null default true,
  primary key (role_id, tool_id, platform_id)
);

create table if not exists hq.ai_requests (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null,
  employee_id uuid references hq.employees(id),
  role_code text not null,
  department_code text,
  platform_slug text,
  session_id text,
  request_source text not null check (request_source in ('central_web','support','mobile','api','scheduled')),
  question text not null,
  tool_codes text[] not null default '{}',
  data_scope jsonb not null default '{}',
  model_used text,
  tokens_used integer,
  latency_ms integer,
  status text not null check (status in ('accepted','denied','completed','failed')),
  created_at timestamptz not null default now()
);

create table if not exists hq.ai_responses (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references hq.ai_requests(id) on delete cascade,
  response_text text not null,
  confidence numeric,
  citations jsonb not null default '[]',
  action_level text not null check (action_level in ('read','prepare','execute')),
  created_at timestamptz not null default now()
);

create table if not exists hq.ai_drafts (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references hq.ai_requests(id) on delete cascade,
  draft_type text not null,
  payload jsonb not null,
  approved_payload jsonb,
  status text not null default 'pending_review' check (status in ('pending_review','approved','rejected','expired')),
  reviewed_by uuid references hq.employees(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_requests_actor_created on hq.ai_requests(employee_id, created_at desc);
create index if not exists idx_ai_requests_source_created on hq.ai_requests(request_source, created_at desc);
create index if not exists idx_ai_drafts_pending on hq.ai_drafts(status, created_at desc);

create table if not exists hq.ai_audit_events (
  id uuid primary key default gen_random_uuid(),
  event jsonb not null,
  created_at timestamptz not null default now()
);
alter table hq.ai_audit_events enable row level security;
revoke all on hq.ai_audit_events from public, anon, authenticated;
grant all on hq.ai_audit_events to service_role;

create or replace function public.hq_ai_audit_event_v1(p_event jsonb)
returns jsonb language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare event_id uuid;
begin
  insert into hq.ai_audit_events(event) values(coalesce(p_event,'{}'::jsonb)) returning id into event_id;
  return jsonb_build_object('id',event_id,'status','recorded');
end $$;
revoke all on function public.hq_ai_audit_event_v1(jsonb) from public, anon, authenticated;
grant execute on function public.hq_ai_audit_event_v1(jsonb) to service_role;

insert into hq.ai_tool_registry(code, description, action_level, data_class) values
 ('get_company_summary','Resumo agregado da empresa','read','operational_aggregate'),
 ('get_pending_approvals','Aprovações pendentes sem executar','read','workflow'),
 ('get_pending_kyc','KYC pendente dentro do âmbito autorizado','read','personal_restricted'),
 ('get_finance_summary','Indicadores financeiros agregados','read','financial_restricted')
on conflict (code) do update set description=excluded.description, action_level=excluded.action_level, data_class=excluded.data_class, active=true;

commit;
