BEGIN;
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
        'source', 'support_message_trigger'
      ),
      p_dispatch_key := 'support_message:' || NEW.id::text || ':' || v_recipient_id::text
    );
  END LOOP;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_support_message_recipients ON public.support_messages;
CREATE TRIGGER trg_notify_support_message_recipients
AFTER INSERT ON public.support_messages
FOR EACH ROW
EXECUTE FUNCTION public.trg_notify_support_message_recipients();
CREATE OR REPLACE FUNCTION public.sell_marketing_event_ticket(
  p_event_id UUID,
  p_buyer_id UUID DEFAULT auth.uid()
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event public.marketing_events%ROWTYPE;
  v_ticket_id UUID;
  v_wallet_id UUID;
  v_commission NUMERIC(12,2);
  v_restaurant_amount NUMERIC(12,2);
  v_price NUMERIC(12,2);
  v_restaurant_owner_id UUID;
  v_restaurant_name TEXT;
BEGIN
  IF p_buyer_id IS NULL OR p_buyer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'buyer_required';
  END IF;

  SELECT *
  INTO v_event
  FROM public.marketing_events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND OR v_event.status <> 'published' OR v_event.sells_tickets IS FALSE THEN
    RAISE EXCEPTION 'event_not_available_for_ticket_sale';
  END IF;

  IF v_event.sales_start_at IS NOT NULL AND now() < v_event.sales_start_at THEN
    RAISE EXCEPTION 'ticket_sales_not_open';
  END IF;

  IF v_event.sales_end_at IS NOT NULL AND now() > v_event.sales_end_at THEN
    RAISE EXCEPTION 'ticket_sales_closed';
  END IF;

  IF v_event.ticket_quantity IS NOT NULL AND v_event.tickets_sold >= v_event.ticket_quantity THEN
    RAISE EXCEPTION 'event_sold_out';
  END IF;

  SELECT owner_id, name
  INTO v_restaurant_owner_id, v_restaurant_name
  FROM public.restaurants
  WHERE id = v_event.restaurant_id;

  v_price := COALESCE(v_event.ticket_price, 0);
  v_commission := round((v_price * 0.10)::numeric, 2);
  v_restaurant_amount := round((v_price - v_commission)::numeric, 2);

  SELECT id
  INTO v_wallet_id
  FROM public.wallets
  WHERE user_id = p_buyer_id
  ORDER BY is_default DESC NULLS LAST, created_at ASC
  LIMIT 1;

  IF v_price > 0 AND v_wallet_id IS NULL THEN
    RAISE EXCEPTION 'wallet_not_found';
  END IF;

  INSERT INTO public.marketing_event_tickets (
    event_id,
    buyer_id,
    price,
    deligo_commission,
    restaurant_amount,
    status,
    sold_at
  )
  VALUES (
    p_event_id,
    p_buyer_id,
    v_price,
    v_commission,
    v_restaurant_amount,
    'sold',
    now()
  )
  RETURNING id INTO v_ticket_id;

  IF v_price > 0 THEN
    PERFORM public.apply_wallet_ledger_entry(
      p_wallet_id := v_wallet_id,
      p_user_id := p_buyer_id,
      p_direction := 'debit',
      p_entry_type := 'event_ticket_purchase',
      p_amount := v_price,
      p_reference_key := 'event_ticket_purchase:' || v_ticket_id::text,
      p_metadata := jsonb_build_object(
        'event_id', p_event_id,
        'ticket_id', v_ticket_id,
        'source', 'deligo_events'
      ),
      p_status := 'confirmed',
      p_allow_negative := false
    );

    PERFORM public.apply_wallet_ledger_entry(
      p_wallet_id := NULL,
      p_user_id := NULL,
      p_direction := 'credit',
      p_entry_type := 'event_ticket_deligo_commission',
      p_amount := v_commission,
      p_reference_key := 'event_ticket_commission:' || v_ticket_id::text,
      p_metadata := jsonb_build_object(
        'event_id', p_event_id,
        'ticket_id', v_ticket_id,
        'source', 'deligo_events',
        'commission_percent', 10
      ),
      p_status := 'confirmed',
      p_allow_negative := true
    );
  END IF;

  UPDATE public.marketing_events
  SET tickets_sold = tickets_sold + 1,
      gross_revenue = gross_revenue + v_price,
      deligo_commission = deligo_commission + v_commission,
      net_amount = net_amount + v_restaurant_amount
  WHERE id = p_event_id;

  UPDATE public.restaurant_event_wallets
  SET balance = balance + v_restaurant_amount,
      available_balance = available_balance + v_restaurant_amount,
      updated_at = now()
  WHERE event_id = p_event_id;

  IF v_restaurant_owner_id IS NOT NULL THEN
    PERFORM public.create_app_notification(
      p_user_id := v_restaurant_owner_id,
      p_type := 'EVENT_TICKET_SOLD',
      p_title := 'Bilhete vendido',
      p_body := COALESCE(NULLIF(trim(v_restaurant_name), ''), 'O restaurante')
        || ' recebeu ' || to_char(v_restaurant_amount, 'FM999999990.00')
        || ' MZN de "' || COALESCE(NULLIF(trim(v_event.title), ''), 'evento') || '".',
      p_action := 'OPEN_RESTAURANT_MARKETING',
      p_entity_id := p_event_id::text,
      p_priority := 'HIGH',
      p_channel := 'marketing',
      p_metadata := jsonb_build_object(
        'event_id', p_event_id,
        'ticket_id', v_ticket_id,
        'buyer_id', p_buyer_id,
        'gross_amount', v_price,
        'restaurant_amount', v_restaurant_amount,
        'deligo_commission', v_commission,
        'commission_percent', 10,
        'source', 'event_ticket_purchase'
      ),
      p_dispatch_key := 'event_ticket_sold:' || v_ticket_id::text || ':' || v_restaurant_owner_id::text
    );
  END IF;

  RETURN v_ticket_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.trg_notify_support_message_recipients() TO service_role;
GRANT EXECUTE ON FUNCTION public.sell_marketing_event_ticket(UUID, UUID) TO authenticated;
COMMIT;
