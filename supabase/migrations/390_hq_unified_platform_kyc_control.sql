begin;

create table if not exists hq.platform_kyc_cases (
  id uuid primary key default gen_random_uuid(),
  platform_id uuid not null references hq.platforms(id),
  source_schema text not null,
  source_table text not null,
  source_record_id text not null,
  subject_user_id uuid references auth.users(id) on delete set null,
  subject_type text not null,
  subject_name text,
  status text not null default 'submitted' check (status in ('submitted','under_review','approved','rejected','suspended','correction_requested','expired')),
  decision_reason text,
  document_references jsonb not null default '[]'::jsonb,
  source_snapshot jsonb not null default '{}'::jsonb,
  submitted_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by_employee_id uuid references hq.employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(platform_id, source_schema, source_table, source_record_id),
  check (jsonb_typeof(document_references) = 'array'),
  check (jsonb_typeof(source_snapshot) = 'object')
);
create index if not exists hq_platform_kyc_cases_queue_idx on hq.platform_kyc_cases(status, platform_id, submitted_at desc);
create index if not exists hq_platform_kyc_cases_subject_idx on hq.platform_kyc_cases(subject_user_id, updated_at desc) where subject_user_id is not null;
alter table hq.platform_kyc_cases enable row level security;
revoke all on hq.platform_kyc_cases from public, anon, authenticated;
grant select, insert, update, delete on hq.platform_kyc_cases to service_role;

create or replace function hq.capture_platform_kyc_case(
  p_platform_slug text, p_source_schema text, p_source_table text, p_source_record_id text,
  p_subject_user_id uuid, p_subject_type text, p_subject_name text, p_status text,
  p_document_references jsonb default '[]'::jsonb, p_source_snapshot jsonb default '{}'::jsonb,
  p_submitted_at timestamptz default now()
) returns void language plpgsql security definer set search_path = hq, public, pg_temp as $$
declare v_platform_id uuid; v_status text;
begin
  select id into v_platform_id from hq.platforms where slug = p_platform_slug and integration_status = 'connected';
  if v_platform_id is null then return; end if;
  v_status := case lower(coalesce(p_status,''))
    when 'approved' then 'approved' when 'rejected' then 'rejected' when 'suspended' then 'suspended'
    when 'requires_update' then 'correction_requested' when 'correction_requested' then 'correction_requested'
    when 'under_review' then 'under_review' else 'submitted' end;
  insert into hq.platform_kyc_cases(platform_id,source_schema,source_table,source_record_id,subject_user_id,subject_type,subject_name,status,document_references,source_snapshot,submitted_at)
  values(v_platform_id,p_source_schema,p_source_table,p_source_record_id,p_subject_user_id,p_subject_type,p_subject_name,v_status,coalesce(p_document_references,'[]'::jsonb),coalesce(p_source_snapshot,'{}'::jsonb),coalesce(p_submitted_at,now()))
  on conflict(platform_id,source_schema,source_table,source_record_id) do update set
    subject_user_id=excluded.subject_user_id, subject_type=excluded.subject_type, subject_name=excluded.subject_name,
    status=excluded.status, document_references=excluded.document_references, source_snapshot=excluded.source_snapshot,
    submitted_at=least(hq.platform_kyc_cases.submitted_at,excluded.submitted_at), updated_at=now();
end;
$$;

create or replace function hq.trg_deligo_kyc_to_hq() returns trigger language plpgsql security definer set search_path=hq,public,pg_temp as $$
begin
  if lower(coalesce(new.role,'')) not in ('courier','restaurant') then return new; end if;
  perform hq.capture_platform_kyc_case('deligo','public','profiles',new.id::text,new.id,
    case when lower(new.role)='courier' then 'courier' else 'restaurant' end,new.full_name,
    case when coalesce(new.is_blocked,false) then 'suspended' else coalesce(new.kyc_status,'pending') end,
    '[]'::jsonb,jsonb_strip_nulls(jsonb_build_object('role',new.role,'kyc_status',new.kyc_status)),new.created_at);
  return new;
end;
$$;

create or replace function hq.trg_sarca_kyc_to_hq() returns trigger language plpgsql security definer set search_path=hq,sarca,public,pg_temp as $$
begin
  perform hq.capture_platform_kyc_case('sarca','sarca','driver_documents',new.id::text,new.driver_user_id,
    'driver_document',new.document_type,new.status,
    jsonb_build_array(jsonb_build_object('bucket','driver-kyc','path',new.storage_path,'label',new.document_type)),
    jsonb_strip_nulls(jsonb_build_object('document_type',new.document_type,'expires_at',new.expires_at)),new.created_at);
  return new;
end;
$$;

create or replace function hq.trg_market_seller_kyc_to_hq() returns trigger language plpgsql security definer set search_path=hq,taomoz,public,pg_temp as $$
begin
  perform hq.capture_platform_kyc_case('taomoz','taomoz','seller_profiles',new.id::text,new.user_id,'seller',new.store_name,new.kyc_status,
    '[]'::jsonb,jsonb_build_object('active',new.is_active),new.created_at);
  return new;
end;
$$;

create or replace function hq.trg_comunhao_kyc_to_hq() returns trigger language plpgsql security definer set search_path=hq,comunhao,public,pg_temp as $$
begin
  perform hq.capture_platform_kyc_case('comunhao','comunhao','churches',new.id::text,new.owner_user_id,'church',new.name,new.status,
    '[]'::jsonb,jsonb_strip_nulls(jsonb_build_object('organization_id',new.organization_id,'status',new.status)),new.created_at);
  return new;
end;
$$;

create or replace function hq.trg_mestre24_kyc_to_hq() returns trigger language plpgsql security definer set search_path=hq,mestre24,public,pg_temp as $$
begin
  perform hq.capture_platform_kyc_case('mestre24','mestre24','kyc_verifications',new.id::text,new.professional_user_id,
    'professional_document',new.document_type,new.status,
    jsonb_build_array(jsonb_build_object('bucket','mestre24-kyc','path',new.storage_path,'label',new.document_type)),
    jsonb_strip_nulls(jsonb_build_object('document_type',new.document_type)),new.created_at);
  return new;
end;
$$;

do $$ begin
  if to_regclass('public.profiles') is not null then
    execute 'drop trigger if exists hq_deligo_kyc_to_hq on public.profiles';
    execute 'create trigger hq_deligo_kyc_to_hq after insert or update of kyc_status,is_blocked on public.profiles for each row execute function hq.trg_deligo_kyc_to_hq()';
  end if;
  if to_regclass('sarca.driver_documents') is not null then
    execute 'drop trigger if exists hq_sarca_kyc_to_hq on sarca.driver_documents';
    execute 'create trigger hq_sarca_kyc_to_hq after insert or update of status on sarca.driver_documents for each row execute function hq.trg_sarca_kyc_to_hq()';
  end if;
  if to_regclass('taomoz.seller_profiles') is not null then
    execute 'drop trigger if exists hq_market_seller_kyc_to_hq on taomoz.seller_profiles';
    execute 'create trigger hq_market_seller_kyc_to_hq after insert or update of kyc_status on taomoz.seller_profiles for each row execute function hq.trg_market_seller_kyc_to_hq()';
  end if;
  if to_regclass('comunhao.churches') is not null then
    execute 'drop trigger if exists hq_comunhao_kyc_to_hq on comunhao.churches';
    execute 'create trigger hq_comunhao_kyc_to_hq after insert or update of status on comunhao.churches for each row execute function hq.trg_comunhao_kyc_to_hq()';
  end if;
  if to_regclass('mestre24.kyc_verifications') is not null then
    execute 'drop trigger if exists hq_mestre24_kyc_to_hq on mestre24.kyc_verifications';
    execute 'create trigger hq_mestre24_kyc_to_hq after insert or update of status on mestre24.kyc_verifications for each row execute function hq.trg_mestre24_kyc_to_hq()';
  end if;
end $$;

create or replace function public.hq_decide_platform_kyc_v1(
  p_case_id uuid, p_actor_auth_user_id uuid, p_decision text, p_reason text default null
) returns jsonb language plpgsql security definer set search_path=hq,public,sarca,taomoz,comunhao,mestre24,pg_temp as $$
declare c hq.platform_kyc_cases; e hq.employees; next_status text;
begin
  if p_decision not in ('approve','reject','suspend','correction') then raise exception 'KYC_DECISION_INVALID'; end if;
  if p_decision <> 'approve' and coalesce(nullif(trim(p_reason),''),'')='' then raise exception 'KYC_REASON_REQUIRED'; end if;
  select * into e from hq.employees where auth_user_id=p_actor_auth_user_id and status='active';
  if e.id is null then raise exception 'HQ_ACTOR_NOT_ACTIVE'; end if;
  select * into c from hq.platform_kyc_cases where id=p_case_id for update;
  if not found then raise exception 'KYC_CASE_NOT_FOUND'; end if;
  next_status := case p_decision when 'approve' then 'approved' when 'reject' then 'rejected' when 'suspend' then 'suspended' else 'correction_requested' end;
  if c.source_schema='public' and c.source_table='profiles' then
    update public.profiles set kyc_status=case p_decision when 'approve' then 'approved' when 'reject' then 'rejected' else 'pending' end,
      is_blocked=case when p_decision='suspend' then true else is_blocked end,
      kyc_rejection_reason=case when p_decision='approve' then null else p_reason end, updated_at=now() where id=c.source_record_id::uuid;
  elsif c.source_schema='sarca' and c.source_table='driver_documents' then
    update sarca.driver_documents set status=case p_decision when 'approve' then 'approved' when 'reject' then 'rejected' else 'pending' end,
      rejection_reason=case when p_decision='approve' then null else p_reason end, reviewed_by_user_id=p_actor_auth_user_id, reviewed_at=now(), updated_at=now() where id=c.source_record_id::uuid;
    if p_decision='suspend' then update sarca.driver_profiles set status='suspended',updated_at=now() where user_id=c.subject_user_id; end if;
  elsif c.source_schema='taomoz' and c.source_table='seller_profiles' then
    update taomoz.seller_profiles set kyc_status=next_status,is_active=case when p_decision in ('reject','suspend') then false else is_active end,updated_at=now() where id=c.source_record_id::uuid;
  elsif c.source_schema='comunhao' and c.source_table='churches' then
    update comunhao.churches set status=case p_decision when 'approve' then 'active' when 'suspend' then 'suspended' else 'pending' end,updated_at=now() where id=c.source_record_id::uuid;
  elsif c.source_schema='mestre24' and c.source_table='kyc_verifications' then
    update mestre24.kyc_verifications set status=next_status,reviewed_by=p_actor_auth_user_id,reviewed_at=now(),reason=case when p_decision='approve' then null else p_reason end where id=c.source_record_id::uuid;
    update mestre24.professional_profiles set verification_status=next_status,visible_in_marketplace=case when p_decision in ('reject','suspend','correction') then false else visible_in_marketplace end,updated_at=now() where user_id=c.subject_user_id;
  else raise exception 'KYC_SOURCE_UNSUPPORTED'; end if;
  update hq.platform_kyc_cases set status=next_status,decision_reason=case when p_decision='approve' then null else p_reason end,decided_at=now(),decided_by_employee_id=e.id,updated_at=now() where id=c.id;
  insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,platform_id,module,target_type,target_id,result,metadata)
  values(e.id,'KYC_'||upper(next_status),'10000000-0000-0000-0000-000000000001',c.platform_id,'kyc','platform_kyc_case',c.id::text,'success',jsonb_build_object('reason',p_reason,'source',c.source_schema||'.'||c.source_table,'source_record_id',c.source_record_id));
  return jsonb_build_object('ok',true,'case_id',c.id,'status',next_status);
end;
$$;

revoke all on function public.hq_decide_platform_kyc_v1(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.hq_decide_platform_kyc_v1(uuid,uuid,text,text) to service_role;
notify pgrst,'reload schema';
commit;
