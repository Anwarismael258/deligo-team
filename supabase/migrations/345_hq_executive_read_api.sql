begin;
create or replace function public.hq_executive_governance_v1()
returns jsonb language plpgsql security definer set search_path=pg_catalog,hq,core,public
as $$
declare supplied_secret text; expected_hash text;
begin
 supplied_secret:=coalesce((current_setting('request.headers',true)::jsonb->>'x-hq-integration-secret'),'');
 select secret_sha256 into expected_hash from core.hq_integration_credentials where integration_key='deligo-triunfal-hq' and active;
 if expected_hash is null or encode(extensions.digest(supplied_secret,'sha256'),'hex')<>expected_hash then raise insufficient_privilege; end if;
 return jsonb_build_object('meetings',coalesce((select jsonb_agg(to_jsonb(x) order by x.scheduled_at desc) from (select id,title,scheduled_at,status,minutes_url from hq.board_meetings limit 50)x),'[]'::jsonb),'decisions',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select d.id,d.title,d.category,d.status,d.due_at,d.approved_at,e.display_name responsible from hq.executive_decisions d left join hq.employees e on e.id=d.responsible_employee_id limit 100)x),'[]'::jsonb),'changes',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,change_type,summary,effective_at,created_at from hq.corporate_change_log limit 100)x),'[]'::jsonb));
end;$$;
revoke all on function public.hq_executive_governance_v1() from public;
grant execute on function public.hq_executive_governance_v1() to service_role;
commit;
