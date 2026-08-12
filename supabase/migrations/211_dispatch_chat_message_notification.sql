CREATE OR REPLACE FUNCTION public.dispatch_chat_message_notification(
  p_order_id UUID,
  p_target_user_id UUID,
  p_sender_name TEXT,
  p_message_preview TEXT,
  p_created_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_id UUID := auth.uid();
  v_order RECORD;
  v_body TEXT;
  v_metadata JSONB;
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required';
  END IF;

  SELECT
    o.id,
    o.client_id,
    o.customer_id,
    o.courier_id,
    r.owner_id AS restaurant_owner_id
  INTO v_order
  FROM public.orders o
  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF v_actor_id = p_target_user_id THEN
    RAISE EXCEPTION 'cannot_notify_self';
  END IF;

  IF v_actor_id IS DISTINCT FROM v_order.client_id
     AND v_actor_id IS DISTINCT FROM v_order.customer_id
     AND v_actor_id IS DISTINCT FROM v_order.courier_id
     AND v_actor_id IS DISTINCT FROM v_order.restaurant_owner_id
     AND NOT public.is_admin()
  THEN
    RAISE EXCEPTION 'actor_not_allowed';
  END IF;

  IF p_target_user_id IS DISTINCT FROM v_order.client_id
     AND p_target_user_id IS DISTINCT FROM v_order.customer_id
     AND p_target_user_id IS DISTINCT FROM v_order.courier_id
     AND p_target_user_id IS DISTINCT FROM v_order.restaurant_owner_id
  THEN
    RAISE EXCEPTION 'target_not_allowed';
  END IF;

  v_body := format(
    '%s: %s',
    COALESCE(NULLIF(btrim(p_sender_name), ''), 'Nova mensagem'),
    CASE
      WHEN char_length(COALESCE(p_message_preview, '')) > 80
        THEN left(COALESCE(p_message_preview, ''), 80) || '...'
      ELSE COALESCE(p_message_preview, '')
    END
  );

  v_metadata := jsonb_build_object(
    'order_id', p_order_id,
    'sender_id', v_actor_id,
    'sender_name', COALESCE(NULLIF(btrim(p_sender_name), ''), 'Nova mensagem'),
    'created_at', COALESCE(p_created_at, NOW())
  );

  RETURN public.create_app_notification(
    p_user_id := p_target_user_id,
    p_type := 'MESSAGE_RECEIVED',
    p_title := 'Nova mensagem',
    p_body := v_body,
    p_action := 'OPEN_CHAT',
    p_entity_id := p_order_id::TEXT,
    p_priority := 'HIGH',
    p_channel := 'chat',
    p_metadata := v_metadata
  );
END;
$$;
REVOKE ALL ON FUNCTION public.dispatch_chat_message_notification(
  UUID,
  UUID,
  TEXT,
  TEXT,
  TIMESTAMPTZ
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dispatch_chat_message_notification(
  UUID,
  UUID,
  TEXT,
  TEXT,
  TIMESTAMPTZ
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_chat_message_notification(
  UUID,
  UUID,
  TEXT,
  TEXT,
  TIMESTAMPTZ
) TO service_role;
