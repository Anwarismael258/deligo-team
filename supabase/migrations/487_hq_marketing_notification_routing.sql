-- Route marketing and communication events to the Central HQ inbox.
-- Additive only: no balances, payments, RLS policies or existing records are changed.

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
    return array['finance.view','finance.transactions.review','finance.transactions.approve','finance.budget.create','finance.expense.create','finance.createExpense','finance.approvePayment','payment.execute','payment.reconcile','accounting.view','payroll.view','reports.view'];
  elsif event_text ~ '(support|ticket|customer|complaint|chat|message|dispute)' then
    return array['support.view','support.manage','support.viewTickets','support.reply','support.close','operations.view','marketing.view'];
  elsif event_text ~ '(news|article|content|marketing|campaign|advert|promotion)' then
    return array['marketing.view','marketing.manage','marketing.publish','news.view','news.review','news.approve','news.publish'];
  elsif event_text ~ '(kyc|field|courier|driver|estafeta|restaurant|vendor|professional)' then
    return array['field.view','field.manage','field.approveKyc','field.kyc.review','field.kyc.decide','operations.view','platforms.view'];
  elsif event_text ~ '(hr|employee|workforce|hiring|offboarding|people|user|payroll)' then
    return array['hr.view','hr.manage','hr.viewEmployees','people.view','payroll.view'];
  elsif event_text ~ '(legal|contract|compliance|risk)' then
    return array['legal.view','legal.manage','legal.viewContracts','legal.approveContract','documents.restricted.view','audit.view'];
  elsif event_text ~ '(technology|incident|outage|security|system)' then
    return array['technology.view','technology.manage','platform.manage','audit.view'];
  elsif event_text ~ '(procurement|purchase|supplier|asset)' then
    return array['procurement.view','procurement.manage','assets.view','assets.manage','operations.view'];
  end if;
  return array['platforms.view','operations.view','reports.view'];
end;
$$;

create or replace function public.hq_notify_inbox_message()
returns trigger
language plpgsql
security definer
set search_path=public,hq,pg_temp
as $$
declare
  row_data jsonb := to_jsonb(new);
  area_text text := lower(coalesce(row_data->>'area',''));
  source_id_text text := row_data->>'id';
  required_permissions text[];
  target text := '/caixa-de-entrada';
begin
  if area_text ~ '(marketing|campaign|restaurant)' then
    required_permissions := array['marketing.view'];
  elsif area_text ~ '(support|customer|apoio)' then
    required_permissions := array['support.view','marketing.view'];
  else
    return new;
  end if;

  perform hq.notify_permissioned_event(
    'inbox-message:'||coalesce(source_id_text,md5(row_data::text)),
    'inbox_message',
    case when area_text ~ '(marketing|campaign|restaurant)' then 'Novo pedido de marketing'
         else 'Nova mensagem de suporte' end,
    concat_ws(' · ',nullif(row_data->>'subject',''),nullif(row_data->>'from_name',''),nullif(row_data->>'from_email','')),
    null,
    target,
    required_permissions,
    'message',
    true,
    'normal',
    null,
    'inbox_message',
    source_id_text
  );
  return new;
end;
$$;

create or replace function public.hq_notify_restaurant_marketing_request()
returns trigger
language plpgsql
security definer
set search_path=public,hq,pg_temp
as $$
declare
  row_data jsonb := to_jsonb(new);
  source_id_text text := row_data->>'id';
begin
  perform hq.notify_permissioned_event(
    'restaurant-marketing-request:'||coalesce(source_id_text,md5(row_data::text)),
    'restaurant_marketing_request',
    'Novo pedido de marketing DeliGo Eats',
    concat_ws(' · ',nullif(row_data->>'campaign_title',''),nullif(row_data->>'request_type',''),nullif(row_data->>'event_name','')),
    null,
    '/marketing',
    array['marketing.view','marketing.manage'],
    'action',
    true,
    'normal',
    null,
    'restaurant_marketing_request',
    source_id_text
  );
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.inbox_messages') is not null then
    drop trigger if exists trg_hq_notify_inbox_message on public.inbox_messages;
    create trigger trg_hq_notify_inbox_message
    after insert on public.inbox_messages
    for each row execute function public.hq_notify_inbox_message();
  end if;
  if to_regclass('public.marketing_requests') is not null then
    drop trigger if exists trg_hq_notify_restaurant_marketing_request on public.marketing_requests;
    create trigger trg_hq_notify_restaurant_marketing_request
    after insert or update of status on public.marketing_requests
    for each row execute function public.hq_notify_restaurant_marketing_request();
  end if;
end;
$$;

revoke all on function public.hq_notify_inbox_message() from public,anon,authenticated;
revoke all on function public.hq_notify_restaurant_marketing_request() from public,anon,authenticated;
grant execute on function public.hq_notify_inbox_message() to service_role;
grant execute on function public.hq_notify_restaurant_marketing_request() to service_role;
