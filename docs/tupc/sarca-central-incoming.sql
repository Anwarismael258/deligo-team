begin;
CREATE OR REPLACE FUNCTION hq.sync_deligo_support_ticket_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'hq'
AS $function$
declare
  v_platform_id uuid := '20000000-0000-0000-0000-000000000001';
  v_reference text := 'deligo:support:' || new.id::text;
  v_status text;
begin
  if lower(coalesce(new.external_source,'')) like '%sarca%' then
    select id into v_platform_id from hq.platforms where slug='sarca';
  end if;
  v_status := case lower(coalesce(new.status, 'open'))
    when 'resolved' then 'resolved'
    when 'closed' then 'closed'
    when 'escalated' then 'escalated'
    when 'waiting_customer' then 'waiting_customer'
    when 'pending' then 'in_analysis'
    when 'in_progress' then 'in_analysis'
    else 'open'
  end;

  insert into hq.support_tickets (
    platform_id, external_reference, customer_reference, subject,
    priority, status, opened_at, resolved_at, ticket_type, category,
    description, customer_name, customer_contact, resolution, closed_at,
    updated_at
  ) values (
    v_platform_id, v_reference, new.opened_by::text,
    coalesce(nullif(trim(new.reason), ''), 'Pedido de apoio DeliGo'),
    'normal', v_status, new.created_at,
    case when v_status in ('resolved','closed') then coalesce(new.resolved_at, now()) end,
    case when new.dispute_type is not null then 'complaint' else 'question' end,
    coalesce(nullif(trim(new.dispute_type), ''), 'general'),
    new.reason, new.customer_name,
    coalesce(nullif(trim(new.customer_phone), ''), nullif(trim(new.customer_email), '')),
    new.resolution,
    case when v_status = 'closed' then coalesce(new.resolved_at, now()) end,
    coalesce(new.updated_at, now())
  )
  on conflict (external_reference) where external_reference is not null
  do update set
    platform_id = excluded.platform_id,
    status = excluded.status,
    subject = excluded.subject,
    description = excluded.description,
    customer_name = excluded.customer_name,
    customer_contact = excluded.customer_contact,
    resolution = excluded.resolution,
    resolved_at = excluded.resolved_at,
    closed_at = excluded.closed_at,
    updated_at = excluded.updated_at;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.hq_decide_platform_kyc_v1(p_case_id uuid, p_actor_auth_user_id uuid, p_decision text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'hq', 'public', 'sarca', 'taomoz', 'comunhao', 'mestre24', 'pg_temp'
AS $function$
declare c hq.platform_kyc_cases; e hq.employees; next_status text;
begin
  if p_decision not in ('approve','reject','suspend','correction') then raise exception 'KYC_DECISION_INVALID'; end if;
  if p_decision <> 'approve' and coalesce(nullif(trim(p_reason),''),'')='' then raise exception 'KYC_REASON_REQUIRED'; end if;
  select * into e from hq.employees where auth_user_id=p_actor_auth_user_id and status='active';
  if e.id is null then raise exception 'HQ_ACTOR_NOT_ACTIVE'; end if;
  select * into c from hq.platform_kyc_cases where id=p_case_id for update;
  if not found then raise exception 'KYC_CASE_NOT_FOUND'; end if;
  if not hq.is_full_admin_employee(e.id) and not exists(select 1 from hq.employee_platforms ep where ep.employee_id=e.id and ep.platform_id=c.platform_id and ep.revoked_at is null and (ep.valid_until is null or ep.valid_until>now())) then raise exception 'KYC_PLATFORM_FORBIDDEN'; end if;
  if not hq.is_full_admin_employee(e.id) and not exists(select 1 from hq.employee_roles er join hq.roles r on r.id=er.role_id where er.employee_id=e.id and er.revoked_at is null and r.active and r.code in ('FINANCE','SUPERVISOR','OPERATIONS','FIELD','COMPLIANCE','LEGAL') and (er.valid_until is null or er.valid_until>now())) then raise exception 'KYC_DECISION_FORBIDDEN'; end if;
  next_status := case p_decision when 'approve' then 'approved' when 'reject' then 'rejected' when 'suspend' then 'suspended' else 'correction_requested' end;
  if c.source_schema='public' and c.source_table='profiles' then
    update public.profiles set kyc_status=case p_decision when 'approve' then 'approved' when 'reject' then 'rejected' else 'pending' end,
      is_blocked=case when p_decision='suspend' then true else is_blocked end,
      kyc_rejection_reason=case when p_decision='approve' then null else p_reason end, updated_at=now() where id=c.source_record_id::uuid;
  elsif c.source_schema='sarca' and c.source_table='driver_documents' then
    update sarca.driver_documents set status=case p_decision when 'approve' then 'approved' when 'reject' then 'rejected' else 'pending' end,
      rejection_reason=case when p_decision='approve' then null else p_reason end, reviewed_by_user_id=p_actor_auth_user_id, reviewed_at=now(), updated_at=now() where id=c.source_record_id::uuid;
    if not found then raise exception 'KYC_SOURCE_NOT_FOUND'; end if;
    if p_decision in ('reject','correction') then update sarca.driver_profiles set status=case when p_decision='reject' then 'rejected' else 'pending' end,updated_at=now() where user_id=c.subject_user_id; end if;
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
$function$
;

-- SARCA documents use pending + review reason for a requested correction.
create or replace function hq.notify_sarca_incoming_v1() returns trigger
language plpgsql security invoker set search_path='' as $$
declare p uuid; key text; typ text; title text; target text;
begin
 if tg_table_name='platform_kyc_cases' then
  p:=new.platform_id; key:='sarca-kyc:'||new.id;typ:='new_kyc';title:='Novo KYC SARCA';target:='/field';
 elsif tg_table_name='support_tickets' then
  p:=new.platform_id;key:='sarca-support:'||new.id;typ:='new_support_ticket';title:='Novo pedido de apoio SARCA';target:='/apoio-cliente';
 else
  if new.sender_type<>'customer' or new.is_internal then return new; end if;
  select platform_id into p from hq.support_tickets where id=new.ticket_id;
  key:='sarca-support-message:'||new.id;typ:='support_message';title:='Nova mensagem no pedido de apoio SARCA';target:='/apoio-cliente';
 end if;
 if not exists(select 1 from hq.platforms where id=p and slug='sarca') then return new; end if;
 perform hq.notify_permissioned_event(key,typ,title,'SARCA · Novo pedido recebido',p,target,
 hq.notification_permissions_for_event(typ,typ,typ),'action',true,'normal',null,typ,new.id::text);
 return new;
end $$;
revoke all on function hq.notify_sarca_incoming_v1() from public,anon,authenticated;
grant execute on function hq.notify_sarca_incoming_v1() to service_role;
drop trigger if exists notify_sarca_kyc_incoming on hq.platform_kyc_cases;
create trigger notify_sarca_kyc_incoming after insert on hq.platform_kyc_cases for each row execute function hq.notify_sarca_incoming_v1();
drop trigger if exists notify_sarca_support_incoming on hq.support_tickets;
create trigger notify_sarca_support_incoming after insert on hq.support_tickets for each row execute function hq.notify_sarca_incoming_v1();
drop trigger if exists notify_sarca_support_message on hq.support_conversations;
create trigger notify_sarca_support_message after insert on hq.support_conversations for each row execute function hq.notify_sarca_incoming_v1();
notify pgrst,'reload schema';
commit;
