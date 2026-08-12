BEGIN;
CREATE OR REPLACE FUNCTION public.trg_notify_wallet_credit_events()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status <> 'confirmed' OR NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.entry_type IN ('order_cancellation_refund', 'order_timeout_refund')
     AND NEW.direction = 'credit' THEN
    PERFORM public.create_app_notification(
      p_user_id := NEW.user_id,
      p_type := 'REFUND_COMPLETED',
      p_title := 'Reembolso concluido 💸',
      p_body := 'O valor do reembolso ja entrou na sua carteira.',
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
  ELSIF NEW.entry_type = 'cashback_reward'
        AND NEW.direction = 'credit'
        AND NEW.reference_key LIKE 'cashback-customer-%' THEN
    PERFORM public.create_app_notification(
      p_user_id := NEW.user_id,
      p_type := 'CASHBACK_RECEIVED',
      p_title := 'Cashback recebido 🎁',
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
CREATE OR REPLACE FUNCTION public.trg_notify_order_delay_events()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_client_id uuid;
BEGIN
  IF NEW.event_type <> 'delivery_sla_exceeded' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(client_id, customer_id)
  INTO v_client_id
  FROM public.orders
  WHERE id = NEW.order_id;

  IF v_client_id IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM public.create_app_notification(
    p_user_id := v_client_id,
    p_type := 'ORDER_DELAYED',
    p_title := 'Pedido atrasado ⚠️',
    p_body := 'A sua entrega esta com atraso. Abra os detalhes para acompanhar.',
    p_action := 'OPEN_ORDER',
    p_entity_id := NEW.order_id::text,
    p_priority := 'HIGH',
    p_channel := 'order',
    p_metadata := jsonb_build_object(
      'order_id', NEW.order_id,
      'event_type', NEW.event_type,
      'source', 'order_events'
    )
  );

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_order_delay_events ON public.order_events;
CREATE TRIGGER trg_notify_order_delay_events
AFTER INSERT ON public.order_events
FOR EACH ROW
EXECUTE FUNCTION public.trg_notify_order_delay_events();
COMMIT;
