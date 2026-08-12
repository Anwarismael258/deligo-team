BEGIN;
ALTER TABLE IF EXISTS public.push_notifications
  ADD COLUMN IF NOT EXISTS app_delivered_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS opened_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_ack_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS delivery_ack_payload JSONB NOT NULL DEFAULT '{}'::jsonb;
CREATE INDEX IF NOT EXISTS idx_push_notifications_app_delivered_at
  ON public.push_notifications(app_delivered_at);
CREATE INDEX IF NOT EXISTS idx_push_notifications_opened_at
  ON public.push_notifications(opened_at);
CREATE OR REPLACE FUNCTION public.ack_push_notification_delivery(
  p_notification_id UUID,
  p_state TEXT DEFAULT 'delivered',
  p_context JSONB DEFAULT '{}'::jsonb
)
RETURNS public.push_notifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_state TEXT := lower(COALESCE(NULLIF(btrim(p_state), ''), 'delivered'));
  v_row public.push_notifications%ROWTYPE;
BEGIN
  IF p_notification_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF v_state NOT IN ('delivered', 'opened') THEN
    v_state := 'delivered';
  END IF;

  UPDATE public.push_notifications
  SET
    app_delivered_at = CASE
      WHEN v_state IN ('delivered', 'opened') THEN COALESCE(app_delivered_at, NOW())
      ELSE app_delivered_at
    END,
    opened_at = CASE
      WHEN v_state = 'opened' THEN COALESCE(opened_at, NOW())
      ELSE opened_at
    END,
    read_at = CASE
      WHEN v_state = 'opened' THEN COALESCE(read_at, NOW())
      ELSE read_at
    END,
    delivery_ack_count = COALESCE(delivery_ack_count, 0) + 1,
    delivery_ack_payload = COALESCE(delivery_ack_payload, '{}'::jsonb)
      || jsonb_build_object(
        'last_state', v_state,
        'last_ack_at', NOW(),
        'last_ack_user_id', COALESCE(v_user_id::text, '')
      )
      || COALESCE(p_context, '{}'::jsonb)
  WHERE id = p_notification_id
    AND (
      ((v_user_id IS NOT NULL) AND user_id = v_user_id)
      OR public.is_admin()
    )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.ack_push_notification_delivery(UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ack_push_notification_delivery(UUID, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ack_push_notification_delivery(UUID, TEXT, JSONB) TO service_role;
COMMIT;
