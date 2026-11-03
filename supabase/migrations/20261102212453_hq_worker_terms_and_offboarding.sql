begin;

create table if not exists hq.worker_terms_versions (
  id uuid primary key default gen_random_uuid(),
  version text not null unique,
  title text not null,
  body jsonb not null default '{}'::jsonb,
  content_hash text not null,
  status text not null default 'pending_review' check (status in ('draft','pending_review','active','archived')),
  created_by uuid references hq.employees(id) on delete set null,
  legal_reviewed_at timestamptz,
  effective_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists hq.worker_terms_acceptances (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references hq.employees(id) on delete restrict,
  terms_version_id uuid not null references hq.worker_terms_versions(id) on delete restrict,
  accepted_at timestamptz not null default now(),
  acceptance_text text not null,
  acceptance_hash text not null,
  ip_address inet,
  user_agent text,
  unique (employee_id, terms_version_id)
);

create table if not exists hq.worker_official_documents (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references hq.employees(id) on delete restrict,
  terms_version_id uuid not null references hq.worker_terms_versions(id) on delete restrict,
  acceptance_id uuid not null references hq.worker_terms_acceptances(id) on delete restrict,
  document_kind text not null default 'worker_terms',
  verification_code text not null unique,
  integrity_hash text not null,
  canonical_payload jsonb not null,
  generated_at timestamptz not null default now(),
  unique (employee_id, terms_version_id)
);

create table if not exists hq.employee_access_history (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references hq.employees(id) on delete restrict,
  actor_employee_id uuid references hq.employees(id) on delete set null,
  event_type text not null,
  previous_status text,
  new_status text,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create index if not exists idx_hq_worker_terms_acceptances_employee on hq.worker_terms_acceptances(employee_id, accepted_at desc);
create index if not exists idx_hq_worker_official_documents_employee on hq.worker_official_documents(employee_id, generated_at desc);
create index if not exists idx_hq_employee_access_history_employee on hq.employee_access_history(employee_id, occurred_at desc);

do $$
declare t text;
begin
  foreach t in array array['worker_terms_versions','worker_terms_acceptances','worker_official_documents','employee_access_history'] loop
    execute format('alter table hq.%I enable row level security', t);
    execute format('revoke all on hq.%I from public, anon, authenticated', t);
    execute format('grant all on hq.%I to service_role', t);
  end loop;
end $$;

create or replace function hq.prevent_worker_history_mutation() returns trigger
language plpgsql security definer set search_path=hq,public,pg_temp as $$
begin
  raise exception 'worker_history_is_append_only';
end $$;

drop trigger if exists trg_worker_terms_acceptances_append_only on hq.worker_terms_acceptances;
create trigger trg_worker_terms_acceptances_append_only before update or delete on hq.worker_terms_acceptances for each row execute function hq.prevent_worker_history_mutation();
drop trigger if exists trg_worker_official_documents_append_only on hq.worker_official_documents;
create trigger trg_worker_official_documents_append_only before update or delete on hq.worker_official_documents for each row execute function hq.prevent_worker_history_mutation();
drop trigger if exists trg_employee_access_history_append_only on hq.employee_access_history;
create trigger trg_employee_access_history_append_only before update or delete on hq.employee_access_history for each row execute function hq.prevent_worker_history_mutation();

create or replace function hq.record_worker_terms_acceptance_v1(
  p_employee_id uuid,
  p_terms_version_id uuid,
  p_acceptance_text text,
  p_acceptance_hash text,
  p_ip_address inet default null,
  p_user_agent text default null
) returns jsonb language plpgsql security definer set search_path=hq,public,pg_temp as $$
declare version_row record; acceptance_row record;
begin
  select * into version_row from hq.worker_terms_versions where id=p_terms_version_id and status='active';
  if version_row.id is null then raise exception 'worker_terms_not_active'; end if;
  if nullif(trim(p_acceptance_text),'') is null or nullif(trim(p_acceptance_hash),'') is null then raise exception 'explicit_acceptance_required'; end if;
  insert into hq.worker_terms_acceptances(employee_id,terms_version_id,acceptance_text,acceptance_hash,ip_address,user_agent)
  values(p_employee_id,p_terms_version_id,trim(p_acceptance_text),trim(p_acceptance_hash),p_ip_address,left(p_user_agent,500))
  on conflict (employee_id,terms_version_id) do nothing
  returning * into acceptance_row;
  if acceptance_row.id is null then
    select * into acceptance_row from hq.worker_terms_acceptances where employee_id=p_employee_id and terms_version_id=p_terms_version_id;
  end if;
  return jsonb_build_object('id',acceptance_row.id,'employee_id',acceptance_row.employee_id,'terms_version_id',acceptance_row.terms_version_id,'accepted_at',acceptance_row.accepted_at,'acceptance_hash',acceptance_row.acceptance_hash);
end $$;

revoke all on function hq.record_worker_terms_acceptance_v1(uuid,uuid,text,text,inet,text) from public,anon,authenticated;
grant execute on function hq.record_worker_terms_acceptance_v1(uuid,uuid,text,text,inet,text) to service_role;

insert into hq.worker_terms_versions(version,title,body,content_hash,status,effective_at)
select '1.0','Termos de trabalho e utilização da Central HQ',
  jsonb_build_object(
    'intro','Documento interno sujeito à validação jurídica e laboral aplicável em Moçambique.',
    'sections',jsonb_build_array(
      jsonb_build_object('title','Identidade e missão','text','A DeliGo Triunfal coordena plataformas digitais e operações integradas através da Central HQ.'),
      jsonb_build_object('title','Funções e responsabilidades','text','CEO define direção e aprova decisões críticas; Finanças gere reconciliação e movimentos financeiros autorizados; Supervisor coordena trabalho; Apoio ao Cliente atende e responde; Marketing prepara comunicação; Campo executa visitas, recolhe evidências e submete KYC.'),
      jsonb_build_object('title','Benefícios e remuneração','text','Benefícios, remuneração e direitos dependem do vínculo profissional e dos documentos aplicáveis ao trabalhador. Este documento não substitui contrato nem legislação.'),
      jsonb_build_object('title','Confidencialidade e dados','text','O trabalhador deve proteger dados pessoais, documentos, credenciais e informação comercial, usando-os apenas para fins autorizados.'),
      jsonb_build_object('title','Contas e operações','text','É proibido partilhar credenciais ou consultar dados sem autorização. Operações administrativas e financeiras devem respeitar o cargo, as aprovações e os registos da Central.'),
      jsonb_build_object('title','Atendimento e incidentes','text','Reclamações e incidentes devem ser registados nos canais oficiais, encaminhados ao responsável e tratados sem ocultar provas relevantes.'),
      jsonb_build_object('title','Acessos e cessação','text','Promoção, despromoção, suspensão e cessação são decisões autorizadas, auditadas e acompanhadas pela revogação dos acessos sob controlo da empresa.'),
      jsonb_build_object('title','Investigação e conflitos','text','A Central conserva registos necessários, limita o acesso ao âmbito autorizado e encaminha conflitos para análise interna e os canais competentes.'),
      jsonb_build_object('title','Denúncias e direitos','text','O trabalhador pode comunicar irregularidades pelos canais internos definidos e exercer os direitos aplicáveis sobre os seus dados pessoais, nos termos da lei.'),
      jsonb_build_object('title','Aceitação expressa','text','A aceitação só ocorre quando o trabalhador confirma expressamente que leu, compreendeu e aceita esta versão. Chegar ao fim do documento não constitui aceitação automática.')
    )
  ),
  md5('deligo-triunfal-worker-terms-v1.0'), 'pending_review', null
where not exists (select 1 from hq.worker_terms_versions where version='1.0');

notify pgrst, 'reload schema';
commit;
