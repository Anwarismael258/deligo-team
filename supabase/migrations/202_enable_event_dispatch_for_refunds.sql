BEGIN;
CREATE OR REPLACE FUNCTION public.order_event_topic(
  p_event_type TEXT,
  p_old_status TEXT DEFAULT NULL,
  p_new_status TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_event_type TEXT := LOWER(COALESCE(btrim(p_event_type), ''));
  v_old_status TEXT := LOWER(COALESCE(btrim(p_old_status), ''));
  v_new_status TEXT := LOWER(COALESCE(btrim(p_new_status), ''));
BEGIN
  IF v_event_type = '' THEN
    RETURN 'ORDER_EVENT_UNKNOWN';
  END IF;

  IF v_event_type = 'status_changed' THEN
    CASE v_new_status
      WHEN 'accepted' THEN RETURN 'ORDER_ACCEPTED';
      WHEN 'preparing' THEN RETURN 'ORDER_PREPARING';
      WHEN 'ready' THEN RETURN 'ORDER_READY';
      WHEN 'courier_assigned' THEN RETURN 'COURIER_ASSIGNED';
      WHEN 'in_transit' THEN RETURN 'ORDER_PICKED_UP';
      WHEN 'arrived' THEN RETURN 'ORDER_ARRIVED';
      WHEN 'delivered' THEN RETURN 'ORDER_DELIVERED';
      WHEN 'completed' THEN RETURN 'ORDER_COMPLETED';
      WHEN 'auto_completed' THEN RETURN 'ORDER_AUTO_COMPLETED';
      WHEN 'cancelled' THEN RETURN 'ORDER_CANCELLED';
      WHEN 'expired' THEN RETURN 'ORDER_EXPIRED';
      WHEN 'disputed' THEN RETURN 'ORDER_DISPUTED';
      ELSE
        RETURN 'ORDER_STATUS_' || UPPER(REPLACE(COALESCE(v_new_status, 'unknown'), ' ', '_'));
    END CASE;
  END IF;

  CASE v_event_type
    WHEN 'order_created' THEN RETURN 'ORDER_CREATED';
    WHEN 'courier_assigned' THEN RETURN 'COURIER_ASSIGNED';
    WHEN 'courier_changed' THEN RETURN 'COURIER_CHANGED';
    WHEN 'courier_unassigned' THEN RETURN 'COURIER_UNASSIGNED';
    WHEN 'pickup_confirmed_by_customer' THEN RETURN 'ORDER_COMPLETED';
    WHEN 'pickup_auto_completed' THEN RETURN 'ORDER_AUTO_COMPLETED';
    WHEN 'delivery_auto_completed' THEN RETURN 'ORDER_AUTO_COMPLETED';
    WHEN 'delivery_problem_reported' THEN RETURN 'ORDER_DISPUTED';
    WHEN 'delivery_extension_requested' THEN RETURN 'DELIVERY_EXTENSION_REQUESTED';
    WHEN 'delivery_otp_issued' THEN RETURN 'DELIVERY_OTP_ISSUED';
    WHEN 'delivery_otp_regenerated' THEN RETURN 'DELIVERY_OTP_REGENERATED';
    WHEN 'delivery_otp_verified_event' THEN RETURN 'ORDER_DELIVERED';
    WHEN 'settlement_processed' THEN RETURN 'PAYMENT_RELEASED';
    WHEN 'refund_issued' THEN RETURN 'REFUND_INITIATED';
    WHEN 'refund_completed' THEN RETURN 'REFUND_COMPLETED';
    WHEN 'restaurant_timeout_cancel_failed' THEN RETURN 'ORDER_TIMEOUT_CANCEL_FAILED';
    WHEN 'pickup_auto_complete_failed' THEN RETURN 'ORDER_AUTO_COMPLETE_FAILED';
    WHEN 'delivery_auto_complete_failed' THEN RETURN 'ORDER_AUTO_COMPLETE_FAILED';
    WHEN 'courier_reassignment_requested' THEN RETURN 'COURIER_REASSIGNMENT_REQUESTED';
    WHEN 'delivery_sla_exceeded' THEN RETURN 'DELIVERY_SLA_EXCEEDED';
    ELSE
      RETURN UPPER(REGEXP_REPLACE(v_event_type, '[^a-z0-9]+', '_', 'g'));
  END CASE;
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
     AND p_type IN (
       'ORDER_ACCEPTED',
       'ORDER_PREPARING',
       'ORDER_READY',
       'ORDER_READY_FOR_PICKUP',
       'DRIVER_ASSIGNED',
       'ORDER_DRIVER_ASSIGNED',
       'ORDER_PICKED_UP',
       'DRIVER_ARRIVED',
       'ORDER_REJECTED',
       'ORDER_CANCELLED',
       'ORDER_DELIVERED',
       'ORDER_AUTO_COMPLETED',
       'REFUND_STARTED',
       'REFUND_COMPLETED'
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
       'ORDER_PREPARING',
       'ORDER_READY',
       'ORDER_READY_FOR_PICKUP',
       'DRIVER_ASSIGNED',
       'ORDER_DRIVER_ASSIGNED',
       'ORDER_PICKED_UP',
       'DRIVER_ARRIVED',
       'ORDER_REJECTED',
       'ORDER_CANCELLED',
       'ORDER_DELIVERED',
       'ORDER_AUTO_COMPLETED',
       'REFUND_STARTED',
       'REFUND_COMPLETED'
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
CREATE OR REPLACE FUNCTION public.trg_notify_wallet_credit_events()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_restaurant_name TEXT := 'o restaurante';
  v_payload JSONB := '{}'::jsonb;
BEGIN
  IF NEW.status <> 'confirmed' OR NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.entry_type = 'order_timeout_refund'
     AND NEW.direction = 'credit' THEN
    SELECT COALESCE(r.name, 'o restaurante')
    INTO v_restaurant_name
    FROM public.orders o
    LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
    WHERE o.id = NEW.order_id;

    v_payload := jsonb_build_object(
      'order_id', NEW.order_id,
      'reference_key', NEW.reference_key,
      'amount', NEW.amount,
      'entry_type', NEW.entry_type,
      'restaurant_name', v_restaurant_name,
      'wallet_ledger_id', NEW.id
    );

    IF NEW.order_id IS NOT NULL THEN
      PERFORM public.append_order_event(
        p_order_id := NEW.order_id,
        p_event_type := 'refund_completed',
        p_actor_id := NEW.user_id,
        p_actor_role := 'system',
        p_payload := v_payload,
        p_idempotency_key := 'refund-completed-ledger-' || NEW.id::text,
        p_correlation_id := NEW.order_id::text
      );
    END IF;

    PERFORM public.create_app_notification(
      p_user_id := NEW.user_id,
      p_type := 'REFUND_COMPLETED',
      p_title := 'Pedido nao confirmado a tempo',
      p_body := 'O restaurante ' || v_restaurant_name || ' nao confirmou o pedido. O valor voltou para a sua conta.',
      p_action := 'OPEN_WALLET',
      p_entity_id := COALESCE(NEW.order_id::text, NEW.reference_key),
      p_priority := 'HIGH',
      p_channel := 'wallet',
      p_metadata := v_payload
    );
  ELSIF NEW.entry_type = 'order_cancellation_refund'
        AND NEW.direction = 'credit' THEN
    v_payload := jsonb_build_object(
      'order_id', NEW.order_id,
      'reference_key', NEW.reference_key,
      'amount', NEW.amount,
      'entry_type', NEW.entry_type,
      'wallet_ledger_id', NEW.id
    );

    IF NEW.order_id IS NOT NULL THEN
      PERFORM public.append_order_event(
        p_order_id := NEW.order_id,
        p_event_type := 'refund_completed',
        p_actor_id := NEW.user_id,
        p_actor_role := 'system',
        p_payload := v_payload,
        p_idempotency_key := 'refund-completed-ledger-' || NEW.id::text,
        p_correlation_id := NEW.order_id::text
      );
    END IF;

    PERFORM public.create_app_notification(
      p_user_id := NEW.user_id,
      p_type := 'REFUND_COMPLETED',
      p_title := 'Reembolso concluido',
      p_body := 'O valor do reembolso ja entrou na sua carteira.',
      p_action := 'OPEN_WALLET',
      p_entity_id := COALESCE(NEW.order_id::text, NEW.reference_key),
      p_priority := 'HIGH',
      p_channel := 'wallet',
      p_metadata := v_payload
    );
  ELSIF NEW.entry_type = 'cashback_reward'
        AND NEW.direction = 'credit'
        AND NEW.reference_key LIKE 'cashback-customer-%' THEN
    PERFORM public.create_app_notification(
      p_user_id := NEW.user_id,
      p_type := 'CASHBACK_RECEIVED',
      p_title := 'Cashback recebido',
      p_body := 'O cashback deste pedido ja entrou na sua carteira.',
      p_action := 'OPEN_WALLET',
      p_entity_id := COALESCE(NEW.order_id::text, NEW.reference_key),
      p_priority := 'HIGH',
      p_channel := 'wallet',
      p_metadata := jsonb_build_object(
        'order_id', NEW.order_id,
        'reference_key', NEW.reference_key,
        'amount', NEW.amount,
        'entry_type', NEW.entry_type
      )
    );
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_wallet_credit_events ON public.wallet_ledger;
CREATE TRIGGER trg_notify_wallet_credit_events
AFTER INSERT ON public.wallet_ledger
FOR EACH ROW
EXECUTE FUNCTION public.trg_notify_wallet_credit_events();
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
    'REFUND_INITIATED',
    'push',
    'customer',
    'send_notification',
    'refund_started_customer',
    TRUE,
    jsonb_build_object(
      'phase', 'event_backbone',
      'enabled_by', '202_enable_event_dispatch_for_refunds'
    )
  ),
  (
    'REFUND_COMPLETED',
    'push',
    'customer',
    'send_notification',
    'refund_completed_customer',
    TRUE,
    jsonb_build_object(
      'phase', 'event_backbone',
      'enabled_by', '202_enable_event_dispatch_for_refunds'
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
COMMIT;
