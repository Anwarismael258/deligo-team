BEGIN;
ALTER TABLE IF EXISTS public.order_event_dispatch_attempts
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
COMMIT;
