create or replace function hq.claim_sarca_kyc_push_v1(p_notification_id uuid,p_worker text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare n public.push_notifications;
begin
 update public.push_notifications set dispatch_status='processing',dispatch_locked_at=now(),dispatch_locked_by=p_worker,dispatch_attempts=dispatch_attempts+1
 where id=p_notification_id and type like 'SARCA_KYC_%' and metadata->>'app'='sarca' and dispatch_attempts<5
 and ((dispatch_status in ('pending','failed') and next_dispatch_attempt_at<=now()) or (dispatch_status='processing' and dispatch_locked_at<now()-interval '2 minutes'))
 returning * into n;
 if not found then return null; end if;
 return to_jsonb(n);
end $$;
revoke all on function hq.claim_sarca_kyc_push_v1(uuid,text) from public,anon,authenticated;
grant execute on function hq.claim_sarca_kyc_push_v1(uuid,text) to service_role;
