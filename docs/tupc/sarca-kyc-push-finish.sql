create or replace function hq.finish_sarca_kyc_push_v1(p_notification_id uuid,p_worker_id text,p_status text,p_delivery jsonb default '{}'::jsonb,p_error text default null) returns void
language plpgsql security invoker set search_path='' as $$
begin
 if p_status not in ('sent','in_app_only','failed') then raise exception 'SARCA_PUSH_STATE_INVALID'; end if;
 update public.push_notifications set dispatch_status=p_status,dispatch_locked_at=null,dispatch_locked_by=null,
 push_dispatched_at=case when p_status in ('sent','in_app_only') then now() else push_dispatched_at end,
 push_last_error=p_error,push_delivery=coalesce(p_delivery,'{}'::jsonb),
 next_dispatch_attempt_at=case when p_status='failed' then now()+make_interval(mins=>least(60,greatest(1,dispatch_attempts*2))) else next_dispatch_attempt_at end
 where id=p_notification_id and type like 'SARCA_KYC_%' and metadata->>'app'='sarca' and dispatch_status='processing' and dispatch_locked_by=p_worker_id;
end $$;
revoke all on function hq.finish_sarca_kyc_push_v1(uuid,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function hq.finish_sarca_kyc_push_v1(uuid,text,text,jsonb,text) to service_role;
