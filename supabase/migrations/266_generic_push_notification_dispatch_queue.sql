BEGIN;
ALTER TABLE public.push_notifications
  ADD COLUMN IF NOT EXISTS dispatch_status TEXT,
  ADD COLUMN IF NOT EXISTS dispatch_attempts INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dispatch_locked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS dispatch_locked_by TEXT,
  ADD COLUMN IF NOT EXISTS next_dispatch_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS push_dispatched_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS push_last_error TEXT,
  ADD COLUMN IF NOT EXISTS push_delivery JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.push_notifications
  DROP CONSTRAINT IF EXISTS push_notifications_dispatch_status_check;
ALTER TABLE public.push_notifications
  ADD CONSTRAINT push_notifications_dispatch_status_check
  CHECK (
    dispatch_status IS NULL
    OR dispatch_status IN (
      'historical',
      'pending',
      'processing',
      'sent',
      'in_app_only',
      'failed',
      'skipped'
    )
  );
UPDATE public.push_notifications
SET dispatch_status = COALESCE(dispatch_status, 'historical')
WHERE dispatch_status IS NULL;
CREATE INDEX IF NOT EXISTS idx_push_notifications_dispatch_queue
  ON public.push_notifications(dispatch_status, next_dispatch_attempt_at, created_at)
  WHERE dispatch_status IN ('pending', 'failed');
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
      ELSE 'pending'
    END;
  END IF;

  NEW.next_dispatch_attempt_at := COALESCE(NEW.next_dispatch_attempt_at, now());
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_assign_push_notification_dispatch_state ON public.push_notifications;
CREATE TRIGGER trg_assign_push_notification_dispatch_state
BEFORE INSERT ON public.push_notifications
FOR EACH ROW
EXECUTE FUNCTION public.trg_assign_push_notification_dispatch_state();
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
    WHERE dispatch_status IN ('pending', 'failed')
      AND COALESCE(next_dispatch_attempt_at, now()) <= now()
      AND (
        dispatch_locked_at IS NULL
        OR dispatch_locked_at < now() - interval '10 minutes'
      )
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
CREATE OR REPLACE FUNCTION public.mark_push_notification_dispatched(
  p_notification_id UUID,
  p_worker_id TEXT,
  p_status TEXT,
  p_delivery JSONB DEFAULT '{}'::jsonb,
  p_error TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT := lower(COALESCE(NULLIF(trim(p_status), ''), 'sent'));
BEGIN
  IF v_status NOT IN ('sent', 'in_app_only', 'failed', 'skipped') THEN
    RAISE EXCEPTION 'invalid_push_dispatch_status';
  END IF;

  UPDATE public.push_notifications
  SET dispatch_status = v_status,
      dispatch_locked_at = NULL,
      dispatch_locked_by = NULL,
      push_dispatched_at = CASE
        WHEN v_status IN ('sent', 'in_app_only') THEN COALESCE(push_dispatched_at, now())
        ELSE push_dispatched_at
      END,
      push_last_error = p_error,
      push_delivery = COALESCE(p_delivery, '{}'::jsonb),
      next_dispatch_attempt_at = CASE
        WHEN v_status = 'failed'
          THEN now() + make_interval(mins => LEAST(60, GREATEST(1, dispatch_attempts * 2)))
        ELSE next_dispatch_attempt_at
      END,
      updated_at = now()
  WHERE id = p_notification_id
    AND (
      dispatch_locked_by = p_worker_id
      OR dispatch_locked_by IS NULL
      OR p_worker_id IS NULL
    );
END;
$$;
CREATE OR REPLACE FUNCTION public.trg_notify_support_message_recipients()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket public.support_tickets%ROWTYPE;
  v_recipient_id UUID;
  v_sender_role TEXT := lower(COALESCE(NEW.sender_role, 'client'));
  v_sender_name TEXT := COALESCE(NULLIF(trim(NEW.sender_name), ''), 'Suporte');
  v_preview TEXT := left(COALESCE(NULLIF(trim(NEW.text), ''), 'Nova mensagem'), 160);
BEGIN
  SELECT *
  INTO v_ticket
  FROM public.support_tickets
  WHERE id = NEW.ticket_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  FOR v_recipient_id IN
    SELECT DISTINCT recipient_id
    FROM (
      SELECT v_ticket.opened_by AS recipient_id
      WHERE v_sender_role IN ('admin', 'support_agent', 'field_agent')
        AND v_ticket.opened_by IS NOT NULL

      UNION ALL

      SELECT v_ticket.assigned_to AS recipient_id
      WHERE v_sender_role NOT IN ('admin', 'support_agent', 'field_agent')
        AND v_ticket.assigned_to IS NOT NULL

      UNION ALL

      SELECT p.id AS recipient_id
      FROM public.profiles p
      WHERE v_sender_role NOT IN ('admin', 'support_agent', 'field_agent')
        AND v_ticket.assigned_to IS NULL
        AND lower(COALESCE(p.role, '')) IN ('admin', 'support_agent')
    ) recipients
    WHERE recipient_id IS NOT NULL
      AND recipient_id IS DISTINCT FROM NEW.sender_id
  LOOP
    PERFORM public.create_app_notification(
      p_user_id := v_recipient_id,
      p_type := 'SUPPORT_MESSAGE_RECEIVED',
      p_title := 'Nova mensagem no suporte',
      p_body := left(v_sender_name || ': ' || v_preview, 220),
      p_action := 'OPEN_SUPPORT_CHAT',
      p_entity_id := NEW.ticket_id::text,
      p_priority := 'HIGH',
      p_channel := 'support',
      p_metadata := jsonb_build_object(
        'support_ticket_id', NEW.ticket_id,
        'support_message_id', NEW.id,
        'sender_id', NEW.sender_id,
        'sender_name', v_sender_name,
        'source', 'support_message_trigger',
        'server_dispatch_required', true
      ),
      p_dispatch_key := 'support_message:' || NEW.id::text || ':' || v_recipient_id::text
    );
  END LOOP;

  RETURN NEW;
END;
$$;
GRANT EXECUTE ON FUNCTION public.claim_pending_push_notifications(TEXT, INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_push_notification_dispatched(UUID, TEXT, TEXT, JSONB, TEXT) TO service_role;
COMMIT;
