begin;
-- A full unique index lets PostgREST perform atomic upserts for parallel intake.
create unique index if not exists uq_hq_notification_delivery on hq.notifications(employee_id,dedupe_key);
notify pgrst,'reload schema';
commit;
