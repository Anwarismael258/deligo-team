begin;

create table if not exists hq.process_events(
  id bigint generated always as identity primary key,
  workflow_case_id uuid not null references hq.workflow_cases(id) on delete cascade,
  platform_id uuid references hq.platforms(id),
  department_id uuid references hq.departments(id),
  actor_employee_id uuid references hq.employees(id),
  event_type text not null,
  title text not null,
  comment text,
  attachment_reference text,
  resource_type text not null,
  resource_id text not null,
  previous_state jsonb not null default '{}'::jsonb,
  current_state jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create table if not exists hq.process_comments(
  id uuid primary key default gen_random_uuid(),
  workflow_case_id uuid not null references hq.workflow_cases(id) on delete cascade,
  author_employee_id uuid not null references hq.employees(id),
  body text not null check(length(trim(body)) between 1 and 4000),
  attachment_reference text,
  created_at timestamptz not null default now(),
  edited_at timestamptz
);

create table if not exists hq.process_comment_mentions(
  id uuid primary key default gen_random_uuid(),
  comment_id uuid not null references hq.process_comments(id) on delete cascade,
  employee_id uuid not null references hq.employees(id) on delete cascade,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  unique(comment_id,employee_id)
);

create table if not exists hq.realtime_events(
  id bigint generated always as identity primary key,
  platform_id uuid references hq.platforms(id),
  department_id uuid references hq.departments(id),
  workflow_case_id uuid references hq.workflow_cases(id) on delete cascade,
  topic text not null,
  resource_type text not null,
  resource_id text not null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_hq_process_events_case_time on hq.process_events(workflow_case_id,occurred_at desc);
create index if not exists idx_hq_process_comments_case_time on hq.process_comments(workflow_case_id,created_at);
create index if not exists idx_hq_process_mentions_employee on hq.process_comment_mentions(employee_id,read_at,created_at desc);
create index if not exists idx_hq_realtime_events_scope on hq.realtime_events(id desc,platform_id,department_id);

alter table hq.process_events enable row level security;
alter table hq.process_comments enable row level security;
alter table hq.process_comment_mentions enable row level security;
alter table hq.realtime_events enable row level security;
revoke all on hq.process_events,hq.process_comments,hq.process_comment_mentions,hq.realtime_events from public,anon,authenticated;
grant all on hq.process_events,hq.process_comments,hq.process_comment_mentions,hq.realtime_events to service_role;
grant usage,select on all sequences in schema hq to service_role;

create or replace function hq.capture_process_change() returns trigger
language plpgsql security definer set search_path=hq,public as $$
declare row_data jsonb:=to_jsonb(new);old_data jsonb:=case when tg_op='UPDATE' then to_jsonb(old) else '{}'::jsonb end;
 case_id uuid;platform uuid;department uuid;actor uuid;resource_id text;event_name text;old_status text;new_status text;
begin
 resource_id:=row_data->>'id';
 begin case_id:=nullif(row_data->>'workflow_case_id','')::uuid;exception when others then case_id:=null;end;
 if case_id is null then select wl.case_id into case_id from hq.workflow_links wl where wl.resource_type=tg_table_name and wl.resource_id=resource_id order by wl.created_at desc limit 1;end if;
 if tg_table_name='workflow_cases' then case_id:=new.id;end if;
 if tg_table_name='workflow_steps' then case_id:=new.case_id;end if;
 begin platform:=nullif(row_data->>'platform_id','')::uuid;exception when others then platform:=null;end;
 begin department:=coalesce(nullif(row_data->>'department_id','')::uuid,nullif(row_data->>'current_department_id','')::uuid);exception when others then department:=null;end;
 begin actor:=coalesce(nullif(row_data->>'decided_by','')::uuid,nullif(row_data->>'reviewed_by','')::uuid,nullif(row_data->>'approved_by','')::uuid,nullif(row_data->>'created_by','')::uuid,nullif(row_data->>'requested_by','')::uuid);exception when others then actor:=null;end;
 old_status:=old_data->>'status';new_status:=row_data->>'status';
 event_name:=case when tg_op='INSERT' then 'created' when old_status is distinct from new_status then 'status_changed' else 'updated' end;
 if case_id is not null then
   if platform is null then select wc.platform_id into platform from hq.workflow_cases wc where wc.id=case_id;end if;
   insert into hq.process_events(workflow_case_id,platform_id,department_id,actor_employee_id,event_type,title,resource_type,resource_id,previous_state,current_state)
   values(case_id,platform,department,actor,event_name,replace(initcap(tg_table_name),'_',' ')||case when old_status is distinct from new_status then ': '||coalesce(new_status,'atualizado') else ' atualizado' end,tg_table_name,resource_id,jsonb_build_object('status',old_status),jsonb_build_object('status',new_status));
 end if;
 insert into hq.realtime_events(platform_id,department_id,workflow_case_id,topic,resource_type,resource_id,event_type,payload)
 values(platform,department,case_id,case when tg_table_name in('payment_requests','financial_transactions') then 'finance' when tg_table_name in('purchase_requests','purchase_orders') then 'procurement' when tg_table_name in('contracts','legal_cases') then 'legal' when tg_table_name like 'field_%' then 'field' when tg_table_name='support_tickets' then 'support' when tg_table_name='marketing_campaigns' then 'marketing' when tg_table_name='employees' then 'people' else 'workflow' end,tg_table_name,resource_id,event_name,jsonb_build_object('status',new_status,'previous_status',old_status));
 return new;
end $$;

do $$declare t text;begin
 foreach t in array array['workflow_cases','workflow_steps','approval_requests','approval_decisions','support_tickets','purchase_requests','payment_requests','contracts','field_kyc_cases','marketing_campaigns','employees']
 loop
  execute format('drop trigger if exists trg_hq_process_change on hq.%I',t);
  execute format('create trigger trg_hq_process_change after insert or update on hq.%I for each row execute function hq.capture_process_change()',t);
 end loop;
end $$;

create or replace function public.hq_add_process_comment_v1(p_case_id uuid,p_actor_employee_id uuid,p_body text,p_attachment_reference text default null) returns jsonb
language plpgsql security definer set search_path=hq,public as $$
declare c hq.workflow_cases%rowtype;m hq.process_comments%rowtype;mentioned record;
begin
 if coalesce(length(trim(p_body)),0)<1 or length(p_body)>4000 then raise exception 'Comentário inválido';end if;
 if not exists(select 1 from hq.employees where id=p_actor_employee_id and status='active') then raise exception 'Utilizador inativo';end if;
 select * into c from hq.workflow_cases where id=p_case_id;if not found then raise exception 'Processo inexistente';end if;
 insert into hq.process_comments(workflow_case_id,author_employee_id,body,attachment_reference) values(c.id,p_actor_employee_id,trim(p_body),nullif(trim(p_attachment_reference),'')) returning * into m;
 insert into hq.process_events(workflow_case_id,platform_id,department_id,actor_employee_id,event_type,title,comment,attachment_reference,resource_type,resource_id)
 values(c.id,c.platform_id,c.current_department_id,p_actor_employee_id,'comment_added','Comentário interno',m.body,m.attachment_reference,'process_comment',m.id::text);
 for mentioned in
   select distinct e.id,e.name from hq.employees e
   where e.status='active' and e.id<>p_actor_employee_id and (
     position(lower('@'||e.employee_code) in lower(p_body))>0
     or position(lower('@'||replace(e.name,' ','')) in lower(p_body))>0
   )
 loop
   insert into hq.process_comment_mentions(comment_id,employee_id) values(m.id,mentioned.id) on conflict do nothing;
   insert into hq.notifications(employee_id,type,title,body,platform_id,target_url)
   values(mentioned.id,'process_mention','Menção em '||c.case_number,left(trim(p_body),240),c.platform_id,'/processos?case='||c.id);
 end loop;
 insert into hq.realtime_events(platform_id,department_id,workflow_case_id,topic,resource_type,resource_id,event_type,payload)
 values(c.platform_id,c.current_department_id,c.id,'process','process_comment',m.id::text,'comment_added',jsonb_build_object('case_number',c.case_number));
 insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,platform_id,module,target_type,target_id,result,correlation_id,metadata)
 values(p_actor_employee_id,'process_comment_added',c.legal_entity_id,c.platform_id,'workflow','workflow_case',c.id::text,'success',c.correlation_id,jsonb_build_object('comment_id',m.id,'has_attachment',m.attachment_reference is not null));
 return to_jsonb(m);
end $$;
revoke all on function public.hq_add_process_comment_v1(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.hq_add_process_comment_v1(uuid,uuid,text,text) to service_role;

do $$begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='hq' and tablename='realtime_events') then alter publication supabase_realtime add table hq.realtime_events;end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='hq' and tablename='process_comments') then alter publication supabase_realtime add table hq.process_comments;end if;
end $$;

commit;
