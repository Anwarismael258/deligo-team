begin;

create table if not exists hq.central_files (
  id uuid primary key default gen_random_uuid(),
  platform_id uuid not null references hq.platforms(id),
  source_system text not null check (source_system in ('deligo','comunhao','sarca','taomoz','hq')),
  source_bucket text not null,
  source_path text not null,
  subject_type text not null,
  subject_id text not null,
  category text not null check (category in ('kyc','support','dispute','delivery_proof','trip_proof','logistics','merchant','church','marketplace','marketing','legal','finance','operational','other')),
  classification text not null default 'restricted' check (classification in ('operational','confidential','restricted')),
  file_name text not null,
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  checksum_sha256 text,
  status text not null default 'active' check (status in ('active','superseded','deleted','quarantined')),
  uploaded_at timestamptz,
  registered_by_employee_id uuid references hq.employees(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (platform_id, source_bucket, source_path)
);

create table if not exists hq.central_file_access_events (
  id bigint generated always as identity primary key,
  file_id uuid not null references hq.central_files(id) on delete cascade,
  actor_employee_id uuid references hq.employees(id) on delete set null,
  action text not null check (action in ('registered','listed','signed_url_requested','downloaded','status_changed')),
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_central_files_platform_subject on hq.central_files(platform_id, subject_type, subject_id, created_at desc);
create index if not exists idx_central_files_category_status on hq.central_files(category, status, created_at desc);
create index if not exists idx_central_file_access_events_file on hq.central_file_access_events(file_id, created_at desc);

alter table hq.central_files enable row level security;
alter table hq.central_file_access_events enable row level security;
revoke all on hq.central_files, hq.central_file_access_events from public, anon, authenticated;
grant all on hq.central_files, hq.central_file_access_events to service_role;

create or replace function hq.register_central_file_v1(
  p_platform_id uuid,
  p_source_system text,
  p_source_bucket text,
  p_source_path text,
  p_subject_type text,
  p_subject_id text,
  p_category text,
  p_classification text,
  p_file_name text,
  p_mime_type text default null,
  p_size_bytes bigint default null,
  p_checksum_sha256 text default null,
  p_uploaded_at timestamptz default null,
  p_registered_by_employee_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
) returns hq.central_files
language plpgsql security definer set search_path = hq, public, pg_temp as $$
declare registered hq.central_files;
begin
  if p_source_path ~* '^https?://' then
    raise exception 'CENTRAL_FILE_PATH_MUST_NOT_BE_A_URL';
  end if;

  insert into hq.central_files(
    platform_id, source_system, source_bucket, source_path, subject_type, subject_id,
    category, classification, file_name, mime_type, size_bytes, checksum_sha256,
    uploaded_at, registered_by_employee_id, metadata
  ) values (
    p_platform_id, p_source_system, p_source_bucket, p_source_path, p_subject_type, p_subject_id,
    p_category, p_classification, p_file_name, p_mime_type, p_size_bytes, p_checksum_sha256,
    coalesce(p_uploaded_at, now()), p_registered_by_employee_id, coalesce(p_metadata, '{}'::jsonb)
  ) on conflict (platform_id, source_bucket, source_path) do update set
    subject_type = excluded.subject_type,
    subject_id = excluded.subject_id,
    category = excluded.category,
    classification = excluded.classification,
    file_name = excluded.file_name,
    mime_type = excluded.mime_type,
    size_bytes = excluded.size_bytes,
    checksum_sha256 = excluded.checksum_sha256,
    uploaded_at = excluded.uploaded_at,
    metadata = hq.central_files.metadata || excluded.metadata,
    status = 'active',
    updated_at = now()
  returning * into registered;

  insert into hq.central_file_access_events(file_id, actor_employee_id, action, metadata)
  values (registered.id, p_registered_by_employee_id, 'registered', jsonb_build_object('source_system', p_source_system));

  return registered;
end;
$$;

revoke all on function hq.register_central_file_v1(uuid,text,text,text,text,text,text,text,text,text,bigint,text,timestamptz,uuid,jsonb) from public, anon, authenticated;
grant execute on function hq.register_central_file_v1(uuid,text,text,text,text,text,text,text,text,text,bigint,text,timestamptz,uuid,jsonb) to service_role;

commit;
