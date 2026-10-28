CREATE OR REPLACE FUNCTION hq.trg_sarca_trip_finance_to_hq()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'hq', 'sarca', 'public', 'pg_temp'
AS $function$
declare payment_state text;
begin
  if new.status <> 'completed' then return new; end if;
  payment_state := case when lower(coalesce(new.payment_status,'')) in ('paid','confirmed','completed','settled') then 'confirmed' else 'pending' end;
  perform hq.capture_platform_financial_event('sarca','sarca.rides','sarca:ride:'||new.id::text||':completion',
    'ride_completion', coalesce(new.final_fare_minor,new.estimated_fare_minor,0)/100.0, payment_state,
    'ride',new.id::text,new.passenger_user_id,coalesce(new.commission_minor,0)/100.0,coalesce(new.driver_net_minor,0)/100.0,
    new.currency_code,new.payment_method,null,coalesce(new.completed_at,new.updated_at,now()));
  return new;
end;
$function$
;
