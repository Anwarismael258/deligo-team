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
     AND p_type IN (
       'ORDER_ACCEPTED',
       'ORDER_READY',
       'ORDER_DELIVERED',
       'ORDER_AUTO_COMPLETED'
     )
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
     AND NEW.type IN (
       'ORDER_ACCEPTED',
       'ORDER_READY',
       'ORDER_DELIVERED',
       'ORDER_AUTO_COMPLETED'
     )
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
    'ORDER_DELIVERED',
    'push',
    'customer',
    'send_notification',
    'order_delivered_customer',
    TRUE,
    jsonb_build_object(
      'phase', 'event_backbone',
      'enabled_by', '195_enable_event_dispatch_for_order_delivered'
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
