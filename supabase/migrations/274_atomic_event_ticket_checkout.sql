BEGIN;
ALTER TABLE public.wallets
  ADD COLUMN IF NOT EXISTS is_default BOOLEAN NOT NULL DEFAULT TRUE;
UPDATE public.wallets
SET is_default = TRUE
WHERE is_default IS DISTINCT FROM TRUE;
CREATE OR REPLACE FUNCTION public.buy_marketing_event_tickets(
  p_event_id UUID,
  p_ticket_type_id UUID DEFAULT NULL,
  p_quantity INTEGER DEFAULT 1
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_id UUID := auth.uid();
  v_ticket_id UUID;
  v_ticket_ids JSONB := '[]'::jsonb;
  v_event_title TEXT;
  v_ticket_type_name TEXT;
  v_index INTEGER;
BEGIN
  IF v_buyer_id IS NULL THEN
    RAISE EXCEPTION 'buyer_required';
  END IF;

  IF p_quantity < 1 OR p_quantity > 20 THEN
    RAISE EXCEPTION 'invalid_ticket_quantity';
  END IF;

  SELECT title INTO v_event_title
  FROM public.marketing_events
  WHERE id = p_event_id;

  IF p_ticket_type_id IS NOT NULL THEN
    SELECT ticket_name INTO v_ticket_type_name
    FROM public.event_ticket_types
    WHERE id = p_ticket_type_id AND event_id = p_event_id;
  END IF;

  FOR v_index IN 1..p_quantity LOOP
    v_ticket_id := public.sell_marketing_event_ticket(
      p_event_id := p_event_id,
      p_buyer_id := v_buyer_id,
      p_ticket_type_id := p_ticket_type_id
    );
    v_ticket_ids := v_ticket_ids || jsonb_build_array(v_ticket_id);
  END LOOP;

  PERFORM public.create_app_notification(
    p_user_id := v_buyer_id,
    p_type := 'EVENT_TICKET_PURCHASED',
    p_title := 'Compra concluida',
    p_body := 'O seu ' || CASE WHEN p_quantity = 1 THEN 'bilhete' ELSE p_quantity::text || ' bilhetes' END ||
      ' para "' || COALESCE(v_event_title, 'Evento DeliGo') || '" foi emitido com sucesso.',
    p_action := 'OPEN_WALLET_TICKETS',
    p_entity_id := p_event_id::text,
    p_priority := 'HIGH',
    p_channel := 'marketing',
    p_metadata := jsonb_build_object(
      'event_id', p_event_id,
      'ticket_ids', v_ticket_ids,
      'ticket_type_id', p_ticket_type_id,
      'ticket_type_name', COALESCE(v_ticket_type_name, 'Normal'),
      'quantity', p_quantity
    ),
    p_dispatch_key := 'event_ticket_purchase:' || v_buyer_id::text || ':' ||
      p_event_id::text || ':' || md5(v_ticket_ids::text)
  );

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'ticket_ids', v_ticket_ids,
    'quantity', p_quantity
  );
END;
$$;
REVOKE ALL ON FUNCTION public.buy_marketing_event_tickets(UUID, UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.buy_marketing_event_tickets(UUID, UUID, INTEGER) TO authenticated;
COMMIT;
