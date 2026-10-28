begin;
create or replace function hq.trg_sarca_new_trip_to_hq() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 perform hq.capture_platform_event('sarca','sarca.rides','sarca:new-trip:'||new.id::text,'new_trip','ride',new.id::text,new.passenger_user_id,null,jsonb_build_object('status',new.status,'title','Nova viagem SARCA'),new.created_at);
 return new;
end $$;
revoke all on function hq.trg_sarca_new_trip_to_hq() from public,anon,authenticated;
grant execute on function hq.trg_sarca_new_trip_to_hq() to service_role;
drop trigger if exists hq_sarca_new_trip_to_hq on sarca.trips;
create trigger hq_sarca_new_trip_to_hq after insert on sarca.trips for each row execute function hq.trg_sarca_new_trip_to_hq();
commit;
