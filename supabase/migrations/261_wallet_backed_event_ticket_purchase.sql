BEGIN;
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
BEGIN
  IF p_buyer_id IS NULL THEN
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

  IF v_event.ticket_quantity IS NOT NULL AND v_event.tickets_sold >= v_event.ticket_quantity THEN
    RAISE EXCEPTION 'event_sold_out';
  END IF;

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

  RETURN v_ticket_id;
END;
$$;
COMMIT;
