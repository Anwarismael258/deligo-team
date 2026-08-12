CREATE OR REPLACE FUNCTION public.build_notification_dispatch_key(
  p_type TEXT,
  p_user_id UUID,
  p_entity_id TEXT,
  p_channel TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN NULLIF(btrim(COALESCE(p_type, '')), '') IS NULL
      OR p_user_id IS NULL
      OR NULLIF(btrim(COALESCE(p_entity_id, '')), '') IS NULL
    THEN NULL
    ELSE
      'notification:'
      || LOWER(btrim(p_type))
      || ':'
      || p_user_id::text
      || ':'
      || btrim(p_entity_id)
      || ':'
      || LOWER(COALESCE(NULLIF(btrim(p_channel), ''), 'system'))
  END;
$$;
CREATE OR REPLACE FUNCTION public.create_app_notification(
  p_user_id UUID,
  p_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_action TEXT DEFAULT NULL,
  p_entity_id TEXT DEFAULT NULL,
  p_priority TEXT DEFAULT 'NORMAL',
  p_channel TEXT DEFAULT 'system',
  p_metadata JSONB DEFAULT '{}'::jsonb,
  p_source_event_id UUID DEFAULT NULL,
  p_dispatch_key TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_dispatch_key TEXT := NULLIF(btrim(p_dispatch_key), '');
BEGIN
  IF v_dispatch_key IS NULL
     AND p_type IN ('ORDER_ACCEPTED', 'ORDER_READY', 'ORDER_AUTO_COMPLETED')
  THEN
    v_dispatch_key := public.build_notification_dispatch_key(
      p_type := p_type,
      p_user_id := p_user_id,
      p_entity_id := p_entity_id,
      p_channel := p_channel
    );
  END IF;

  IF v_dispatch_key IS NOT NULL THEN
    SELECT id
    INTO v_id
    FROM public.push_notifications
    WHERE dispatch_key = v_dispatch_key
    LIMIT 1;

    IF v_id IS NOT NULL THEN
      RETURN v_id;
    END IF;
  END IF;

  INSERT INTO public.push_notifications (
    user_id,
    type,
    title,
    body,
    action,
    entity_id,
    priority,
    channel,
    data,
    metadata,
    source_event_id,
    dispatch_key,
    created_at
  )
  VALUES (
    p_user_id,
    p_type,
    p_title,
    p_body,
    p_action,
    p_entity_id,
    COALESCE(NULLIF(btrim(p_priority), ''), 'NORMAL'),
    COALESCE(NULLIF(btrim(p_channel), ''), 'system'),
    COALESCE(p_metadata, '{}'::jsonb),
    COALESCE(p_metadata, '{}'::jsonb),
    p_source_event_id,
    v_dispatch_key,
    NOW()
  )
  RETURNING id
  INTO v_id;

  RETURN v_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.trg_assign_push_notification_dispatch_key()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NULLIF(btrim(COALESCE(NEW.dispatch_key, '')), '') IS NULL
     AND NEW.type IN ('ORDER_ACCEPTED', 'ORDER_READY', 'ORDER_AUTO_COMPLETED')
  THEN
    NEW.dispatch_key := public.build_notification_dispatch_key(
      p_type := NEW.type,
      p_user_id := NEW.user_id,
      p_entity_id := NEW.entity_id,
      p_channel := NEW.channel
    );
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_assign_push_notification_dispatch_key ON public.push_notifications;
CREATE TRIGGER trg_assign_push_notification_dispatch_key
BEFORE INSERT OR UPDATE ON public.push_notifications
FOR EACH ROW
EXECUTE FUNCTION public.trg_assign_push_notification_dispatch_key();
INSERT INTO public.order_event_subscriptions (
  event_topic,
  channel,
  target_role,
  handler,
  template_key,
  enabled,
  metadata
)
VALUES
  (
    'ORDER_ACCEPTED',
    'push',
    'customer',
    'send_notification',
    'order_accepted_customer',
    TRUE,
    jsonb_build_object(
      'phase', 'event_backbone',
      'enabled_by', '194_enable_event_dispatch_for_order_acceptance_and_ready'
    )
  ),
  (
    'ORDER_READY',
    'push',
    'customer',
    'send_notification',
    'order_ready_customer',
    TRUE,
    jsonb_build_object(
      'phase', 'event_backbone',
      'enabled_by', '194_enable_event_dispatch_for_order_acceptance_and_ready'
    )
  )
ON CONFLICT (event_topic, channel, target_role, handler)
DO UPDATE
SET
  template_key = EXCLUDED.template_key,
  enabled = TRUE,
  metadata = COALESCE(public.order_event_subscriptions.metadata, '{}'::jsonb)
    || EXCLUDED.metadata,
  updated_at = NOW();
