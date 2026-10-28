begin;
create or replace function hq.reconcile_sarca_driver_kyc_v1(p_driver_id uuid,p_case_id uuid,p_decision text,p_reason text default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare d sarca.driver_profiles; all_docs boolean; complete_profile boolean; n uuid; key text; typ text; title_text text; message_text text; payload jsonb; document_name text; next_status text;
begin
 select * into d from sarca.driver_profiles where user_id=p_driver_id for update;
 if not found then raise exception 'SARCA_DRIVER_NOT_FOUND'; end if;
 select subject_name into document_name from hq.platform_kyc_cases where id=p_case_id and subject_user_id=p_driver_id and source_schema='sarca';
 if not found then raise exception 'SARCA_KYC_CASE_MISMATCH'; end if;
 if p_decision not in ('approve','reject','correction','suspend') then raise exception 'KYC_DECISION_INVALID'; end if;
 if p_decision<>'approve' and nullif(btrim(p_reason),'') is null then raise exception 'KYC_REASON_REQUIRED'; end if;
 select count(*)=10 and bool_and(status='approved' and coalesce(nullif(file_path,''),nullif(storage_path,'')) is not null and (expires_at is null or expires_at>now()))
 into all_docs from (
  select distinct on(document_type) document_type,status,file_path,storage_path,expires_at
  from sarca.driver_documents where driver_user_id=p_driver_id and document_type=any(array['bi_front','bi_back','selfie','driver_license','vehicle_registration','vehicle_front','vehicle_back','vehicle_side','vehicle_interior','vehicle_with_driver'])
  order by document_type,created_at desc,id desc
 ) latest;
 complete_profile:=d.onboarding_completed and d.onboarding_submitted_at is not null and d.terms_accepted_at is not null
 and nullif(btrim(d.personal_id_number),'') is not null and nullif(btrim(d.licence_number),'') is not null
 and exists(select 1 from public.profiles p where (p.user_id=p_driver_id or p.id=p_driver_id) and nullif(btrim(p.full_name),'') is not null)
 and exists(select 1 from sarca.vehicles v where v.driver_user_id=p_driver_id and v.is_active and nullif(btrim(v.vehicle_type),'') is not null and nullif(btrim(v.make),'') is not null and nullif(btrim(v.model),'') is not null and nullif(btrim(v.plate_number),'') is not null and v.year>0 and nullif(btrim(v.service_class),'') is not null);
 if p_decision='approve' then
  if not coalesce(all_docs and complete_profile,false) or d.status='suspended' then
   return jsonb_build_object('driver_user_id',p_driver_id,'driver_status',d.status,'driver_activated',false,'message','Documento aprovado. O perfil só fica activo depois de todos os documentos e dados obrigatórios estarem aprovados.');
  end if;
  next_status:='active';typ:='SARCA_KYC_APPROVED';title_text:='Perfil SARCA aprovado';message_text:='O seu perfil de motorista foi aprovado. Já pode entrar no SARCA e começar a trabalhar.';
 else
  next_status:=case p_decision when 'reject' then 'rejected' when 'suspend' then 'suspended' else 'pending' end;
  typ:=case p_decision when 'reject' then 'SARCA_KYC_REJECTED' when 'suspend' then 'SARCA_KYC_SUSPENDED' else 'SARCA_KYC_CORRECTION_REQUESTED' end;
  title_text:=case p_decision when 'reject' then 'KYC SARCA rejeitado' when 'suspend' then 'Perfil SARCA suspenso' else 'Correção solicitada no KYC SARCA' end;
  message_text:=case p_decision when 'correction' then 'Corrija e envie novamente o documento '||coalesce(document_name,'')||': ' else coalesce(document_name,'Documento')||': ' end||btrim(p_reason);
 end if;
 update sarca.driver_profiles set status=next_status,onboarding_reviewed_at=now(),
 rejection_reason=case when p_decision='approve' then null else message_text end,
 onboarding_completed=case when p_decision in ('correction','reject') then false else onboarding_completed end,
 is_online=case when next_status='active' then is_online else false end,updated_at=now() where user_id=p_driver_id;
 key:='sarca-kyc:'||p_driver_id||':'||md5(concat_ws('|',coalesce(d.onboarding_submitted_at::text,''),case when p_decision='approve' then 'application' else p_case_id::text end,p_decision,coalesce(btrim(p_reason),'')));
 payload:=jsonb_build_object('app','sarca','platform','sarca','route','/driver/onboarding','action','OPEN_DRIVER_ONBOARDING','driver_user_id',p_driver_id,'case_id',p_case_id,'decision',p_decision,'status',next_status,'reason',p_reason,'document_type',document_name);
 insert into public.push_notifications(user_id,type,title,body,channel,action,entity_id,data,metadata,dispatch_key)
 values(p_driver_id,typ,title_text,message_text,'kyc','OPEN_DRIVER_ONBOARDING',p_driver_id::text,payload,payload||jsonb_build_object('dispatch_source','sarca_central_kyc'),key)
 on conflict(dispatch_key) do nothing returning id into n;
 if n is null then select id into n from public.push_notifications where dispatch_key=key; end if;
 insert into public.notifications(id,user_id,type,message,payload) values(n,p_driver_id,typ,message_text,payload||jsonb_build_object('title',title_text,'notification_id',n)) on conflict(id) do nothing;
 return jsonb_build_object('driver_user_id',p_driver_id,'driver_status',next_status,'driver_activated',next_status='active','notification_id',n,'message',title_text);
end $$;
revoke all on function hq.reconcile_sarca_driver_kyc_v1(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function hq.reconcile_sarca_driver_kyc_v1(uuid,uuid,text,text) to service_role;
CREATE OR REPLACE FUNCTION public.hq_decide_platform_kyc_v1(p_case_id uuid, p_actor_auth_user_id uuid, p_decision text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'hq', 'public', 'sarca', 'taomoz', 'comunhao', 'mestre24', 'pg_temp'
AS $function$
declare c hq.platform_kyc_cases; e hq.employees; next_status text; sarca_result jsonb:='{}'::jsonb;
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
  if c.source_schema='sarca' and c.source_table='driver_documents' then
    sarca_result:=hq.reconcile_sarca_driver_kyc_v1(c.subject_user_id,c.id,p_decision,p_reason);
  end if;
  insert into hq.audit_logs(actor_employee_id,action,legal_entity_id,platform_id,module,target_type,target_id,result,metadata)
  values(e.id,'KYC_'||upper(next_status),'10000000-0000-0000-0000-000000000001',c.platform_id,'kyc','platform_kyc_case',c.id::text,'success',jsonb_build_object('reason',p_reason,'source',c.source_schema||'.'||c.source_table,'source_record_id',c.source_record_id));
  return jsonb_build_object('ok',true,'case_id',c.id,'status',next_status)||sarca_result;
end;
$function$
;
notify pgrst,'reload schema';
commit;
