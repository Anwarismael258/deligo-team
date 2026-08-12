BEGIN;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE SCHEMA IF NOT EXISTS vault;
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;
DELETE FROM vault.secrets
WHERE name IN ('comunhao_project_url', 'comunhao_publishable_key');
SELECT vault.create_secret(
  'https://tpmsgvkdjzoidvyiwwfk.supabase.co',
  'comunhao_project_url',
  'Central Comunhao Supabase URL for scheduled Edge Function calls'
);
SELECT vault.create_secret(
  'sb_publishable_VPBqfA_NVrvTs3fRqA49iw_NdOhXRTC',
  'comunhao_publishable_key',
  'Central Comunhao publishable key for scheduled Edge Function calls'
);
DO $unschedule$
BEGIN
  PERFORM cron.unschedule('comunhao-daily-scripture-engine');
EXCEPTION WHEN OTHERS THEN NULL;
END
$unschedule$;
SELECT cron.schedule(
  'comunhao-daily-scripture-engine',
  '5 22 * * *',
  $job$
    SELECT net.http_post(
      url := (
        SELECT decrypted_secret
        FROM vault.decrypted_secrets
        WHERE name = 'comunhao_project_url'
        LIMIT 1
      ) || '/functions/v1/daily-scripture-engine',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'comunhao_publishable_key'
          LIMIT 1
        ),
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'comunhao_publishable_key'
          LIMIT 1
        )
      ),
      body := jsonb_build_object(
        'source', 'supabase_cron',
        'job', 'comunhao-daily-scripture-engine'
      )
    );
  $job$
);
DO $unschedule$
BEGIN
  PERFORM cron.unschedule('comunhao-maintain-calendar-occurrences');
EXCEPTION WHEN OTHERS THEN NULL;
END
$unschedule$;
SELECT cron.schedule(
  'comunhao-maintain-calendar-occurrences',
  '10 22 * * *',
  $job$ SELECT comunhao.maintain_event_occurrences_all(); $job$
);
DO $unschedule$
BEGIN
  PERFORM cron.unschedule('comunhao-event-internal-reminders');
EXCEPTION WHEN OTHERS THEN NULL;
END
$unschedule$;
SELECT cron.schedule(
  'comunhao-event-internal-reminders',
  '*/30 * * * *',
  $job$
    SELECT comunhao.prepare_event_internal_reminders_all();
    SELECT comunhao.dispatch_due_event_internal_reminders(100);
  $job$
);
COMMIT;
