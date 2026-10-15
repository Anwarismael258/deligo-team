begin;

create or replace function hq.capture_process_change() returns trigger
language plpgsql security definer set search_path=hq,public as $$
declare
 row_data jsonb:=to_jsonb(new);
 old_data jsonb:=case when tg_op='UPDATE' then to_jsonb(old) else '{}'::jsonb end;
 case_id uuid; platform uuid; department uuid; actor uuid;
 v_resource_id text; event_name text; old_status text; new_status text;
begin
 v_resource_id:=row_data->>'id';
 begin case_id:=nullif(row_data->>'workflow_case_id','')::uuid; exception when others then case_id:=null; end;
 if case_id is null then
   select wl.case_id into case_id from hq.workflow_links wl
   where wl.resource_type=tg_table_name and wl.resource_id=v_resource_id
   order by wl.created_at desc limit 1;
 end if;
 if tg_table_name='workflow_cases' then case_id:=new.id; end if;
 if tg_table_name='workflow_steps' then case_id:=new.case_id; end if;
 begin platform:=nullif(row_data->>'platform_id','')::uuid; exception when others then platform:=null; end;
 begin department:=coalesce(nullif(row_data->>'department_id','')::uuid,nullif(row_data->>'current_department_id','')::uuid); exception when others then department:=null; end;
 begin actor:=coalesce(nullif(row_data->>'decided_by','')::uuid,nullif(row_data->>'reviewed_by','')::uuid,nullif(row_data->>'approved_by','')::uuid,nullif(row_data->>'created_by','')::uuid,nullif(row_data->>'requested_by','')::uuid); exception when others then actor:=null; end;
 old_status:=old_data->>'status'; new_status:=row_data->>'status';
 event_name:=case when tg_op='INSERT' then 'created' when old_status is distinct from new_status then 'status_changed' else 'updated' end;
 if case_id is not null then
   if platform is null then select wc.platform_id into platform from hq.workflow_cases wc where wc.id=case_id; end if;
   insert into hq.process_events(workflow_case_id,platform_id,department_id,actor_employee_id,event_type,title,resource_type,resource_id,previous_state,current_state)
   values(case_id,platform,department,actor,event_name,replace(initcap(tg_table_name),'_',' ')||case when old_status is distinct from new_status then ': '||coalesce(new_status,'atualizado') else ' atualizado' end,tg_table_name,v_resource_id,jsonb_build_object('status',old_status),jsonb_build_object('status',new_status));
 end if;
 insert into hq.realtime_events(platform_id,department_id,workflow_case_id,topic,resource_type,resource_id,event_type,payload)
 values(platform,department,case_id,case when tg_table_name in('payment_requests','financial_transactions') then 'finance' when tg_table_name in('purchase_requests','purchase_orders') then 'procurement' when tg_table_name in('contracts','legal_cases') then 'legal' when tg_table_name like 'field_%' then 'field' when tg_table_name='support_tickets' then 'support' when tg_table_name='marketing_campaigns' then 'marketing' when tg_table_name='employees' then 'people' else 'workflow' end,tg_table_name,v_resource_id,event_name,jsonb_build_object('status',new_status,'previous_status',old_status));
 return new;
end $$;

commit;
