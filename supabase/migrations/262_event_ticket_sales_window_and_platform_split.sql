BEGIN;
ALTER TABLE public.marketing_events
  ADD COLUMN IF NOT EXISTS sales_start_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sales_end_at TIMESTAMPTZ;
CREATE OR REPLACE FUNCTION public.approve_marketing_request_and_publish(
  p_request_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.marketing_requests%ROWTYPE;
  v_event_id UUID;
  v_owner_id UUID;
BEGIN
  SELECT *
  INTO v_request
  FROM public.marketing_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'marketing_request_not_found';
  END IF;

  SELECT owner_id
  INTO v_owner_id
  FROM public.restaurants
  WHERE id = v_request.restaurant_id;

  IF auth.uid() IS DISTINCT FROM v_owner_id
     AND NOT public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']) THEN
    RAISE EXCEPTION 'not_allowed_to_publish_marketing_request';
  END IF;

  INSERT INTO public.marketing_events (
    request_id,
    restaurant_id,
    title,
    description,
    event_type,
    event_date,
    event_time,
    location,
    poster_url,
    banner_url,
    sells_tickets,
    ticket_price,
    ticket_quantity,
    sales_start_at,
    sales_end_at,
    status,
    published_at
  )
  VALUES (
    v_request.id,
    v_request.restaurant_id,
    COALESCE(NULLIF(trim(v_request.campaign_title), ''), v_request.event_name),
    COALESCE(NULLIF(trim(v_request.campaign_description), ''), v_request.description),
    v_request.request_type,
    v_request.event_date,
    v_request.event_time,
    v_request.location,
    v_request.poster_url,
    v_request.banner_url,
    v_request.sells_tickets,
    v_request.ticket_price,
    v_request.ticket_quantity,
    v_request.sales_start_at,
    v_request.sales_end_at,
    'published',
    now()
  )
  ON CONFLICT (request_id) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    poster_url = EXCLUDED.poster_url,
    banner_url = EXCLUDED.banner_url,
    sells_tickets = EXCLUDED.sells_tickets,
    ticket_price = EXCLUDED.ticket_price,
    ticket_quantity = EXCLUDED.ticket_quantity,
    sales_start_at = EXCLUDED.sales_start_at,
    sales_end_at = EXCLUDED.sales_end_at,
    updated_at = now()
  RETURNING id INTO v_event_id;

  INSERT INTO public.restaurant_event_wallets (restaurant_id, event_id)
  VALUES (v_request.restaurant_id, v_event_id)
  ON CONFLICT (restaurant_id, event_id) DO NOTHING;

  INSERT INTO public.marketing_event_metrics (event_id)
  VALUES (v_event_id)
  ON CONFLICT (event_id) DO NOTHING;

  UPDATE public.marketing_requests
  SET status = 'published',
      restaurant_approved_at = COALESCE(restaurant_approved_at, now()),
      published_at = COALESCE(published_at, now())
  WHERE id = p_request_id;

  INSERT INTO public.marketing_request_messages (
    request_id, sender_id, sender_role, body
  )
  VALUES (
    p_request_id,
    COALESCE(auth.uid(), v_owner_id),
    CASE WHEN auth.uid() = v_owner_id THEN 'restaurant' ELSE 'marketing_agent' END,
    'O evento foi aprovado e publicado automaticamente na DeliGo.'
  );

  RETURN v_event_id;
END;
$$;
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

  RETURN v_ticket_id;
END;
$$;
COMMIT;
