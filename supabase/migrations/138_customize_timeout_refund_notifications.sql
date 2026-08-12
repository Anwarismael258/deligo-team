BEGIN;
CREATE OR REPLACE FUNCTION public.trg_notify_wallet_credit_events()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_restaurant_name text := 'o restaurante';
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

    PERFORM public.create_app_notification(
      p_user_id := NEW.user_id,
      p_type := 'REFUND_COMPLETED',
      p_title := 'Pedido nao confirmado a tempo',
      p_body := 'O restaurante ' || v_restaurant_name || ' nao confirmou o pedido. O valor voltou para a sua conta.',
      p_action := 'OPEN_WALLET',
      p_entity_id := COALESCE(NEW.order_id::text, NEW.reference_key),
      p_priority := 'HIGH',
      p_channel := 'wallet',
      p_metadata := jsonb_build_object(
        'order_id', NEW.order_id,
        'reference_key', NEW.reference_key,
        'amount', NEW.amount,
        'entry_type', NEW.entry_type,
        'restaurant_name', v_restaurant_name
      )
    );
  ELSIF NEW.entry_type = 'order_cancellation_refund'
        AND NEW.direction = 'credit' THEN
    PERFORM public.create_app_notification(
      p_user_id := NEW.user_id,
      p_type := 'REFUND_COMPLETED',
      p_title := 'Reembolso concluido',
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
COMMIT;
