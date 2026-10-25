BEGIN;

-- Compatibilidade para produtores que usam o estado "queued".
-- Mantém pending/failed para filas e registos anteriores.
ALTER TABLE public.push_notifications
  DROP CONSTRAINT IF EXISTS push_notifications_dispatch_status_check;

ALTER TABLE public.push_notifications
  ADD CONSTRAINT push_notifications_dispatch_status_check
  CHECK (
    dispatch_status IS NULL
    OR dispatch_status IN (
      'historical', 'queued', 'pending', 'processing', 'sent',
      'in_app_only', 'failed', 'skipped'
    )
  );

CREATE INDEX IF NOT EXISTS idx_push_notifications_queued_dispatch
  ON public.push_notifications(dispatch_status, next_dispatch_attempt_at, created_at)
  WHERE dispatch_status IN ('queued', 'pending', 'failed');

CREATE OR REPLACE FUNCTION public.trg_assign_push_notification_dispatch_state()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_source TEXT := lower(COALESCE(NEW.metadata->>'dispatch_source', NEW.data->>'dispatch_source', ''));
BEGIN
  IF NEW.dispatch_status IS NULL THEN
    NEW.dispatch_status := CASE
      WHEN NEW.source_event_id IS NOT NULL THEN 'sent'
      WHEN v_source IN ('app_direct', 'notification_dispatch_control') THEN 'sent'
      ELSE 'queued'
    END;
  END IF;
  NEW.next_dispatch_attempt_at := COALESCE(NEW.next_dispatch_attempt_at, now());
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_pending_push_notifications(
  p_worker_id TEXT,
  p_limit INTEGER DEFAULT 50
)
RETURNS SETOF public.push_notifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH candidates AS (
    SELECT id
    FROM public.push_notifications
    WHERE dispatch_status IN ('queued', 'pending', 'failed')
      AND COALESCE(next_dispatch_attempt_at, now()) <= now()
      AND (dispatch_locked_at IS NULL OR dispatch_locked_at < now() - interval '10 minutes')
      AND COALESCE(dispatch_attempts, 0) < 5
    ORDER BY created_at ASC
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 100))
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.push_notifications n
  SET dispatch_status = 'processing',
      dispatch_locked_at = now(),
      dispatch_locked_by = p_worker_id,
      dispatch_attempts = COALESCE(dispatch_attempts, 0) + 1,
      updated_at = now()
  FROM candidates c
  WHERE n.id = c.id
  RETURNING n.*;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_pending_push_notifications(TEXT, INTEGER) TO service_role;
NOTIFY pgrst, 'reload schema';
COMMIT;
