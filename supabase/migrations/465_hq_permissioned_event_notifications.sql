begin;

-- Central notification routing:
-- every event is fanned out to active employees who have the permission
-- required by the event and, when present, access to its platform.
create or replace function hq.notification_permissions_for_event(
  p_source_type text,
  p_event_type text,
  p_entity_type text
) returns text[]
language plpgsql
immutable
set search_path=hq,public,pg_temp
as $$
declare
  event_text text := lower(concat_ws(' ',p_source_type,p_event_type,p_entity_type));
begin
  if event_text ~ '(finance|payment|transaction|refund|payout|wallet|transfer|salary|payroll|subscription)' then
    return array[
      'finance.view',
      'finance.transactions.review',
      'finance.transactions.approve',
      'finance.budget.create',
      'finance.expense.create',
      'finance.createExpense',
      'finance.approvePayment',
      'payment.execute',
      'payment.reconcile',
      'accounting.view',
      'payroll.view',
      'reports.view'
    ];
  elsif event_text ~ '(support|ticket|customer|complaint|chat|message|dispute)' then
    return array[
      'support.view',
      'support.manage',
      'support.viewTickets',
      'support.reply',
      'support.close',
      'operations.view'
    ];
  elsif event_text ~ '(kyc|field|courier|driver|estafeta|restaurant|vendor|professional)' then
    return array[
      'field.view',
      'field.manage',
      'field.approveKyc',
      'field.kyc.review',
      'field.kyc.decide',
      'operations.view',
      'platforms.view'
    ];
  elsif event_text ~ '(news|article|content|marketing|campaign|advert)' then
    return array[
      'marketing.view',
      'marketing.manage',
      'marketing.publish',
      'news.view',
      'news.review',
      'news.approve',
      'news.publish'
    ];
  elsif event_text ~ '(hr|employee|workforce|hiring|offboarding|people|user|payroll)' then
    return array[
      'hr.view',
      'hr.manage',
      'hr.viewEmployees',
      'people.view',
      'payroll.view'
    ];
  elsif event_text ~ '(legal|contract|compliance|risk)' then
    return array[
      'legal.view',
      'legal.manage',
      'legal.viewContracts',
      'legal.approveContract',
      'documents.restricted.view',
      'audit.view'
    ];
  elsif event_text ~ '(technology|incident|outage|security|system)' then
    return array[
      'technology.view',
      'technology.manage',
      'platform.manage',
      'audit.view'
    ];
  elsif event_text ~ '(procurement|purchase|supplier|asset)' then
    return array[
      'procurement.view',
      'procurement.manage',
      'assets.view',
      'assets.manage',
      'operations.view'
    ];
  end if;

  return array['platforms.view','operations.view','reports.view'];
end;
$$;

create or replace function hq.notify_permissioned_event(
  p_event_key text,
  p_type text,
  p_title text,
  p_body text,
  p_platform_id uuid,
  p_target_url text,
  p_required_permissions text[],
  p_category text,
  p_action_required boolean,
  p_priority text,
  p_origin_department_id uuid,
  p_source_type text,
  p_source_id text
) returns integer
language plpgsql
security definer
set search_path=hq,public,pg_temp
as $$
declare
  inserted_count integer := 0;
  permission_codes text[] := coalesce(nullif(p_required_permissions,'{}'::text[]),array['platforms.view']::text[]);
begin
  if coalesce(trim(p_event_key),'') = '' then
    return 0;
  end if;

  insert into hq.notifications(
    employee_id,type,title,body,platform_id,target_url,
    origin_department_id,priority,responsible_employee_id,
    source_type,source_id,dedupe_key,category,action_required,
    channel_policy
  )
  select
    e.id,
    coalesce(nullif(p_type,''),'information'),
    p_title,
    p_body,
    p_platform_id,
    coalesce(nullif(p_target_url,''),'/'),
    p_origin_department_id,
    coalesce(nullif(p_priority,''),'normal'),
    e.id,
    p_source_type,
    p_source_id,
    p_event_key||':'||e.id::text,
    case
      when p_category in ('action','approval','task','deadline','alert','information','message','system')
        then p_category
      else 'information'
    end,
    coalesce(p_action_required,false),
    jsonb_build_object('central',true)
  from hq.employees e
  where e.status='active'
    and (
      exists(
        select 1
        from hq.employee_roles er
        join hq.roles r on r.id=er.role_id
        where er.employee_id=e.id
          and r.code='SUPER_ADMIN'
          and r.active
          and er.revoked_at is null
          and (er.valid_until is null or er.valid_until>now())
      )
      or exists(
        select 1
        from unnest(permission_codes) required(code)
        where not exists(
          select 1
          from hq.employee_permission_overrides denied
          where denied.employee_id=e.id
            and denied.permission_code=required.code
            and denied.allowed=false
        )
        and (
          exists(
            select 1
            from hq.employee_roles er
            join hq.roles r on r.id=er.role_id and r.active
            join hq.role_permissions rp on rp.role_id=r.id and rp.effect='allow'
            join hq.permissions p on p.id=rp.permission_id and p.code=required.code
            where er.employee_id=e.id
              and er.revoked_at is null
              and (er.valid_until is null or er.valid_until>now())
          )
          or exists(
            select 1
            from hq.employee_permission_overrides allowed
            where allowed.employee_id=e.id
              and allowed.permission_code=required.code
              and allowed.allowed=true
          )
        )
      )
    )
    and (
      p_platform_id is null
      or exists(
        select 1
        from hq.employee_roles er
        join hq.roles r on r.id=er.role_id
        where er.employee_id=e.id
          and r.code='SUPER_ADMIN'
          and r.active
          and er.revoked_at is null
          and (er.valid_until is null or er.valid_until>now())
      )
      or exists(
        select 1
        from hq.employee_platforms ep
        where ep.employee_id=e.id
          and ep.platform_id=p_platform_id
          and ep.revoked_at is null
          and (ep.valid_until is null or ep.valid_until>now())
      )
    )
  on conflict(employee_id,dedupe_key) where dedupe_key is not null do nothing;

  get diagnostics inserted_count=row_count;
  return inserted_count;
end;
$$;

revoke all on function hq.notify_permissioned_event(
  text,text,text,text,uuid,text,text[],text,boolean,text,uuid,text,text
) from public,anon,authenticated;
grant execute on function hq.notify_permissioned_event(
  text,text,text,text,uuid,text,text[],text,boolean,text,uuid,text,text
) to service_role;

-- Replace department fan-out with permissioned fan-out. Existing workflow
-- callers keep working, but a department alone no longer grants visibility.
create or replace function hq.notify_department(
  p_department uuid,
  p_type text,
  p_title text,
  p_body text,
  p_platform uuid,
  p_url text
) returns void
language plpgsql
security definer
set search_path=hq,public,pg_temp
as $$
declare
  department_code text;
begin
  select code into department_code from hq.departments where id=p_department;
  perform hq.notify_permissioned_event(
    'department:'||coalesce(department_code,p_department::text)||':'||
      md5(coalesce(p_type,'')||':'||coalesce(p_title,'')||':'||coalesce(p_body,'')),
    p_type,
    p_title,
    p_body,
    p_platform,
    p_url,
    hq.notification_permissions_for_event('department',coalesce(department_code,p_type),p_type),
    case when lower(coalesce(p_type,''))~'(approval|review|action)' then 'approval' else 'information' end,
    lower(coalesce(p_type,''))~'(approval|review|action|pending)',
    'normal',
    p_department,
    'department',
    coalesce(department_code,p_department::text)
  );
end;
$$;

create or replace function hq.notify_assignment_event()
returns trigger
language plpgsql
security definer
set search_path=hq,public,pg_temp
as $$
declare
  row_data jsonb := to_jsonb(new);
  status_text text := lower(coalesce(to_jsonb(new)->>'status','created'));
  source_kind text;
  title_text text;
  body_text text;
  url_text text;
  priority_text text := coalesce(to_jsonb(new)->>'priority','normal');
  platform_value uuid;
  origin_value uuid;
  required_permissions text[];
  category_text text;
  action_required boolean := false;
  source_id_text text := row_data->>'id';
begin
  if tg_table_name='tasks' and status_text in ('completed','cancelled') then return new; end if;
  if tg_table_name='approval_requests' and status_text not in ('submitted','under_review') then return new; end if;
  if tg_table_name='internal_requests' and status_text in ('closed','archived') then return new; end if;
  if tg_table_name='support_tickets' and status_text in ('resolved','closed') then return new; end if;
  if tg_table_name='workforce_requests' and status_text in ('completed','cancelled','rejected') then return new; end if;

  begin platform_value:=nullif(row_data->>'platform_id','')::uuid; exception when others then platform_value:=null; end;
  begin
    origin_value:=coalesce(
      nullif(row_data->>'department_id','')::uuid,
      nullif(row_data->>'current_department_id','')::uuid,
      nullif(row_data->>'target_department_id','')::uuid
    );
  exception when others then origin_value:=null;
  end;

  if tg_table_name='tasks' then
    source_kind:='task'; title_text:='Nova tarefa atribuída'; body_text:=row_data->>'title'; url_text:='/minhas-tarefas'; category_text:='task'; action_required:=true;
  elsif tg_table_name='approval_requests' then
    source_kind:='approval'; title_text:='Pedido aguardando aprovação'; body_text:=row_data->>'title'; url_text:='/aprovacoes'; category_text:='approval'; action_required:=true;
  elsif tg_table_name='internal_requests' then
    source_kind:='internal_request'; title_text:=case when status_text='resolved' then 'Pedido interno respondido' else 'Pedido interno atualizado' end; body_text:=coalesce(row_data->>'subject',row_data->>'title'); url_text:='/apoio-interno'; category_text:='message'; action_required:=status_text not in ('resolved','closed');
  elsif tg_table_name='support_tickets' then
    source_kind:='support_ticket'; title_text:='Ticket encaminhado'; body_text:=concat_ws(' · ',nullif(row_data->>'ticket_number',''),coalesce(row_data->>'subject',row_data->>'title')); url_text:='/apoio-cliente'; category_text:='action'; action_required:=true;
  elsif tg_table_name='workforce_requests' then
    source_kind:='workforce_request'; title_text:=case when row_data->>'request_type'='hiring' then 'Trabalhador em processo de admissão' else 'Trabalhador em processo de desligamento' end; body_text:=coalesce(row_data->>'candidate_name',row_data->>'reason'); url_text:='/recursos-humanos'; category_text:='approval'; action_required:=true; priority_text:='high';
  elsif tg_table_name='field_kyc_cases' then
    source_kind:='field_kyc_case'; title_text:='Documento KYC enviado'; body_text:='Novo processo KYC para revisão'; url_text:='/field'; category_text:='approval'; action_required:=true; priority_text:='high';
  elsif tg_table_name='compliance_risks' then
    source_kind:='compliance_risk'; title_text:='Risco crítico identificado'; body_text:=row_data->>'title'; url_text:='/conformidade-risco'; category_text:='alert'; action_required:=true; priority_text:=case when coalesce((row_data->>'risk_score')::numeric,0)>=20 then 'critical' else 'high' end;
  elsif tg_table_name='technology_incidents' then
    source_kind:='technology_incident'; title_text:='Incidente técnico aberto'; body_text:=row_data->>'title'; url_text:='/tecnologia'; category_text:='alert'; action_required:=true; priority_text:=case when row_data->>'severity'='sev1' then 'critical' when row_data->>'severity'='sev2' then 'urgent' else 'high' end;
  elsif tg_table_name='marketing_campaigns' then
    source_kind:='campaign'; title_text:='Campanha aguardando aprovação'; body_text:=row_data->>'title'; url_text:='/marketing'; category_text:='approval'; action_required:=true;
  else
    return new;
  end if;

  required_permissions:=hq.notification_permissions_for_event(source_kind,status_text,tg_table_name);
  perform hq.notify_permissioned_event(
    source_kind||':'||coalesce(source_id_text,md5(row_data::text))||':'||status_text,
    source_kind,
    coalesce(title_text,'Novo evento da Central'),
    coalesce(body_text,'Foi registado um novo evento.'),
    platform_value,
    url_text,
    required_permissions,
    category_text,
    action_required,
    priority_text,
    origin_value,
    source_kind,
    source_id_text
  );
  return new;
end;
$$;

-- Platform stream: all connected products reach the same permissioned inbox.
create or replace function hq.notify_platform_event()
returns trigger
language plpgsql
security definer
set search_path=hq,public,pg_temp
as $$
declare
  event_status text := lower(coalesce(new.payload->>'status',new.payload->>'state',new.event_type));
  category_text text := case when event_status~'(failed|cancelled|rejected|blocked|urgent|dispute)' then 'alert' else 'information' end;
  action_required boolean := event_status~'(pending|failed|cancelled|rejected|blocked|urgent|dispute|review)';
  target_url text := case
    when lower(new.entity_type)~'(payment|transaction|wallet|transfer|subscription)' then '/financas'
    when lower(new.entity_type)~'(support|ticket|complaint|message)' then '/apoio-cliente'
    when lower(new.entity_type)~'(kyc|professional|courier|restaurant)' then '/field'
    when lower(new.entity_type)~'(news|campaign|content|advert)' then '/marketing'
    else '/'
  end;
begin
  perform hq.notify_permissioned_event(
    'platform-event:'||new.id::text||':'||new.event_type,
    'platform_event',
    coalesce(nullif(new.payload->>'title',''),initcap(replace(new.event_type,'_',' '))),
    initcap(replace(new.source_app,'_',' '))||' · '||
      initcap(replace(new.entity_type,'_',' '))||' · '||new.entity_id,
    new.platform_id,
    target_url,
    hq.notification_permissions_for_event('platform_event',new.event_type,new.entity_type),
    category_text,
    action_required,
    case when event_status~'(failed|rejected|blocked)' then 'urgent' else 'normal' end,
    null,
    'platform_event',
    new.id::text
  );
  return new;
end;
$$;

drop trigger if exists trg_hq_permissioned_platform_event on hq.platform_events;
create trigger trg_hq_permissioned_platform_event
after insert or update of event_type,payload,occurred_at on hq.platform_events
for each row execute function hq.notify_platform_event();

create or replace function hq.notify_financial_event()
returns trigger
language plpgsql
security definer
set search_path=hq,public,pg_temp
as $$
declare
  status_text text := lower(new.payment_status);
  category_text text := case when status_text in ('failed','refunded','reversed','cancelled') then 'alert' else 'information' end;
begin
  perform hq.notify_permissioned_event(
    'financial-event:'||new.id::text||':'||status_text,
    'financial_event',
    'Movimento financeiro '||initcap(replace(new.transaction_type,'_',' ')),
    coalesce(new.reference,new.entity_type,new.source_app)||' · estado: '||status_text||
      ' · '||to_char(new.gross_amount,'FM999G999G990D00')||' '||new.currency,
    new.platform_id,
    '/financas',
    hq.notification_permissions_for_event('financial_event',new.transaction_type,new.entity_type),
    category_text,
    status_text in ('pending','failed','refunded','reversed','cancelled'),
    case when status_text in ('failed','reversed') then 'urgent' when status_text='pending' then 'high' else 'normal' end,
    null,
    'financial_event',
    new.id::text
  );
  return new;
end;
$$;

drop trigger if exists trg_hq_permissioned_financial_event on hq.platform_financial_events;
create trigger trg_hq_permissioned_financial_event
after insert or update of payment_status,transaction_type,gross_amount,occurred_at
on hq.platform_financial_events
for each row execute function hq.notify_financial_event();

create or replace function hq.notify_process_event()
returns trigger
language plpgsql
security definer
set search_path=hq,public,pg_temp
as $$
declare
  event_status text := lower(coalesce(new.current_state->>'status',new.event_type));
begin
  perform hq.notify_permissioned_event(
    'process-event:'||new.id::text,
    'process_event',
    new.title,
    coalesce(new.comment,'Atualização de processo: '||new.event_type),
    new.platform_id,
    case
      when lower(new.resource_type)~'(finance|payment|transaction)' then '/financas'
      when lower(new.resource_type)~'(support|ticket)' then '/apoio-cliente'
      when lower(new.resource_type)~'(kyc|field)' then '/field'
      when lower(new.resource_type)~'(marketing|campaign|news)' then '/marketing'
      else '/'
    end,
    hq.notification_permissions_for_event('process_event',new.event_type,new.resource_type),
    case when event_status~'(failed|rejected|blocked)' then 'alert' when new.event_type~'(approval|review)' then 'approval' else 'information' end,
    event_status~'(pending|failed|rejected|blocked|review|approval)',
    case when event_status~'(failed|rejected|blocked)' then 'urgent' else 'normal' end,
    new.department_id,
    'process_event',
    new.resource_id
  );
  return new;
end;
$$;

drop trigger if exists trg_hq_permissioned_process_event on hq.process_events;
create trigger trg_hq_permissioned_process_event
after insert on hq.process_events
for each row execute function hq.notify_process_event();

commit;
