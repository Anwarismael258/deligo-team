BEGIN;
CREATE TABLE IF NOT EXISTS public.marketing_request_ticket_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.marketing_requests(id) ON DELETE CASCADE,
  ticket_name TEXT NOT NULL CHECK (length(trim(ticket_name)) > 0),
  price NUMERIC(12,2) NOT NULL CHECK (price > 0),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'inactive', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_marketing_request_ticket_types_request_id
  ON public.marketing_request_ticket_types(request_id);
CREATE TABLE IF NOT EXISTS public.event_ticket_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.marketing_events(id) ON DELETE CASCADE,
  ticket_name TEXT NOT NULL CHECK (length(trim(ticket_name)) > 0),
  price NUMERIC(12,2) NOT NULL CHECK (price > 0),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  sold INTEGER NOT NULL DEFAULT 0 CHECK (sold >= 0),
  remaining INTEGER GENERATED ALWAYS AS (GREATEST(quantity - sold, 0)) STORED,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'inactive', 'sold_out', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (event_id, ticket_name)
);
CREATE INDEX IF NOT EXISTS idx_event_ticket_types_event_id
  ON public.event_ticket_types(event_id);
ALTER TABLE public.marketing_event_tickets
  ADD COLUMN IF NOT EXISTS ticket_type_id UUID REFERENCES public.event_ticket_types(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS ticket_type_name TEXT;
ALTER TABLE public.marketing_events
  DROP CONSTRAINT IF EXISTS marketing_events_status_check;
ALTER TABLE public.marketing_events
  ADD CONSTRAINT marketing_events_status_check
  CHECK (status IN (
    'draft',
    'in_review',
    'needs_changes',
    'published',
    'sold_out',
    'completed',
    'rejected',
    'cancelled'
  ));
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
  v_total_quantity INTEGER;
  v_base_ticket RECORD;
BEGIN
  SELECT *
  INTO v_request
  FROM public.marketing_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'marketing_request_not_found';
  END IF;

  IF NOT public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']) THEN
    RAISE EXCEPTION 'not_allowed_to_publish_marketing_request';
  END IF;

  SELECT *
  INTO v_base_ticket
  FROM public.marketing_request_ticket_types
  WHERE request_id = p_request_id
    AND status = 'active'
  ORDER BY price ASC, created_at ASC
  LIMIT 1;

  SELECT COALESCE(sum(quantity), 0)::integer
  INTO v_total_quantity
  FROM public.marketing_request_ticket_types
  WHERE request_id = p_request_id
    AND status = 'active';

  INSERT INTO public.marketing_events (
    request_id,
    restaurant_id,
    title,
    description,
    event_type,
    event_category,
    event_type_detail,
    event_date,
    event_time,
    event_end_time,
    location,
    max_capacity,
    poster_url,
    banner_url,
    sells_tickets,
    ticket_price,
    ticket_quantity,
    ticket_options,
    rules,
    refund_policy,
    status,
    published_at
  )
  VALUES (
    v_request.id,
    v_request.restaurant_id,
    COALESCE(NULLIF(trim(v_request.campaign_title), ''), v_request.event_name),
    COALESCE(NULLIF(trim(v_request.campaign_description), ''), v_request.description),
    v_request.request_type,
    v_request.event_category,
    v_request.event_type_detail,
    v_request.event_date,
    v_request.event_time,
    v_request.event_end_time,
    v_request.location,
    v_request.max_capacity,
    COALESCE(NULLIF(trim(v_request.poster_url), ''), NULLIF(trim(v_request.banner_url), '')),
    v_request.banner_url,
    v_request.sells_tickets,
    CASE WHEN v_base_ticket.id IS NULL THEN v_request.ticket_price ELSE v_base_ticket.price END,
    CASE WHEN v_total_quantity > 0 THEN v_total_quantity ELSE v_request.ticket_quantity END,
    '[]'::jsonb,
    v_request.rules,
    v_request.refund_policy,
    'published',
    now()
  )
  ON CONFLICT (request_id) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    event_type = EXCLUDED.event_type,
    event_category = EXCLUDED.event_category,
    event_type_detail = EXCLUDED.event_type_detail,
    event_date = EXCLUDED.event_date,
    event_time = EXCLUDED.event_time,
    event_end_time = EXCLUDED.event_end_time,
    location = EXCLUDED.location,
    max_capacity = EXCLUDED.max_capacity,
    poster_url = EXCLUDED.poster_url,
    banner_url = EXCLUDED.banner_url,
    sells_tickets = EXCLUDED.sells_tickets,
    ticket_price = EXCLUDED.ticket_price,
    ticket_quantity = EXCLUDED.ticket_quantity,
    ticket_options = '[]'::jsonb,
    rules = EXCLUDED.rules,
    refund_policy = EXCLUDED.refund_policy,
    updated_at = now()
  RETURNING id INTO v_event_id;

  INSERT INTO public.event_ticket_types (
    event_id,
    ticket_name,
    price,
    quantity,
    status
  )
  SELECT
    v_event_id,
    ticket_name,
    price,
    quantity,
    status
  FROM public.marketing_request_ticket_types
  WHERE request_id = p_request_id
    AND status = 'active'
  ON CONFLICT (event_id, ticket_name) DO UPDATE SET
    price = EXCLUDED.price,
    quantity = EXCLUDED.quantity,
    status = EXCLUDED.status;

  IF v_request.sells_tickets IS TRUE
     AND NOT EXISTS (
       SELECT 1 FROM public.event_ticket_types WHERE event_id = v_event_id
     )
     AND v_request.ticket_price IS NOT NULL
     AND v_request.ticket_quantity IS NOT NULL THEN
    INSERT INTO public.event_ticket_types (
      event_id,
      ticket_name,
      price,
      quantity,
      status
    )
    VALUES (
      v_event_id,
      'Normal',
      v_request.ticket_price,
      v_request.ticket_quantity,
      'active'
    )
    ON CONFLICT (event_id, ticket_name) DO NOTHING;
  END IF;

  INSERT INTO public.restaurant_event_wallets (restaurant_id, event_id)
  VALUES (v_request.restaurant_id, v_event_id)
  ON CONFLICT (restaurant_id, event_id) DO NOTHING;

  INSERT INTO public.marketing_event_metrics (event_id)
  VALUES (v_event_id)
  ON CONFLICT (event_id) DO NOTHING;

  UPDATE public.marketing_requests
  SET status = 'published',
      published_at = COALESCE(published_at, now()),
      updated_at = now()
  WHERE id = p_request_id;

  INSERT INTO public.marketing_request_messages (
    request_id, sender_id, sender_role, body
  )
  VALUES (
    p_request_id,
    auth.uid(),
    'marketing_agent',
    'O evento foi aprovado pelo Marketing e publicado automaticamente na DeliGo.'
  );

  RETURN v_event_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.sell_marketing_event_ticket(
  p_event_id UUID,
  p_buyer_id UUID DEFAULT auth.uid(),
  p_ticket_type_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event public.marketing_events%ROWTYPE;
  v_ticket_type public.event_ticket_types%ROWTYPE;
  v_has_ticket_types BOOLEAN := FALSE;
  v_ticket_id UUID;
  v_buyer_wallet public.wallets%ROWTYPE;
  v_restaurant_wallet public.wallets%ROWTYPE;
  v_platform_wallet public.wallets%ROWTYPE;
  v_commission NUMERIC(12,2);
  v_restaurant_amount NUMERIC(12,2);
  v_price NUMERIC(12,2);
  v_ticket_type_name TEXT;
  v_restaurant_owner_id UUID;
  v_restaurant_name TEXT;
  v_platform_user_id UUID;
  v_platform_percent NUMERIC(5,2) := 10;
  v_merchant_percent NUMERIC(5,2) := 90;
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

  SELECT EXISTS (
    SELECT 1
    FROM public.event_ticket_types
    WHERE event_id = p_event_id
      AND status = 'active'
  )
  INTO v_has_ticket_types;

  IF v_has_ticket_types THEN
    IF p_ticket_type_id IS NULL THEN
      RAISE EXCEPTION 'ticket_type_required';
    END IF;

    SELECT *
    INTO v_ticket_type
    FROM public.event_ticket_types
    WHERE id = p_ticket_type_id
      AND event_id = p_event_id
    FOR UPDATE;

    IF NOT FOUND OR v_ticket_type.status <> 'active' THEN
      RAISE EXCEPTION 'ticket_type_unavailable';
    END IF;

    IF v_ticket_type.sold >= v_ticket_type.quantity THEN
      UPDATE public.event_ticket_types
      SET status = 'sold_out'
      WHERE id = v_ticket_type.id;
      RAISE EXCEPTION 'event_sold_out';
    END IF;

    v_price := COALESCE(v_ticket_type.price, 0);
    v_ticket_type_name := v_ticket_type.ticket_name;
  ELSE
    IF v_event.ticket_quantity IS NOT NULL AND v_event.tickets_sold >= v_event.ticket_quantity THEN
      RAISE EXCEPTION 'event_sold_out';
    END IF;
    v_price := COALESCE(v_event.ticket_price, 0);
    v_ticket_type_name := 'Normal';
  END IF;

  SELECT platform_percent, merchant_percent
  INTO v_platform_percent, v_merchant_percent
  FROM public.commission_rules
  WHERE type = 'event_ticket'
    AND active IS TRUE
  LIMIT 1;

  v_platform_percent := COALESCE(v_platform_percent, 10);
  v_merchant_percent := COALESCE(v_merchant_percent, 100 - v_platform_percent);

  SELECT owner_id, name
  INTO v_restaurant_owner_id, v_restaurant_name
  FROM public.restaurants
  WHERE id = v_event.restaurant_id;

  v_platform_user_id := public.resolve_platform_user_id();
  v_commission := round((v_price * v_platform_percent / 100)::numeric, 2);
  v_restaurant_amount := round((v_price * v_merchant_percent / 100)::numeric, 2);

  SELECT *
  INTO v_buyer_wallet
  FROM public.wallets
  WHERE user_id = p_buyer_id
  ORDER BY is_default DESC NULLS LAST, created_at ASC
  LIMIT 1;

  IF v_price > 0 AND v_buyer_wallet.id IS NULL THEN
    RAISE EXCEPTION 'wallet_not_found';
  END IF;

  INSERT INTO public.marketing_event_tickets (
    event_id,
    buyer_id,
    ticket_type_id,
    ticket_type_name,
    price,
    deligo_commission,
    restaurant_amount,
    status,
    sold_at
  )
  VALUES (
    p_event_id,
    p_buyer_id,
    CASE WHEN v_has_ticket_types THEN p_ticket_type_id ELSE NULL END,
    v_ticket_type_name,
    v_price,
    v_commission,
    v_restaurant_amount,
    'sold',
    now()
  )
  RETURNING id INTO v_ticket_id;

  IF v_price > 0 THEN
    PERFORM public.apply_wallet_ledger_entry(
      p_wallet_id := v_buyer_wallet.id,
      p_user_id := p_buyer_id,
      p_direction := 'debit',
      p_entry_type := 'event_ticket_purchase',
      p_amount := v_price,
      p_reference_key := 'event_ticket_purchase:' || v_ticket_id::text,
      p_metadata := jsonb_build_object(
        'event_id', p_event_id,
        'ticket_id', v_ticket_id,
        'ticket_type_id', p_ticket_type_id,
        'ticket_type_name', v_ticket_type_name,
        'source', 'deligo_events'
      ),
      p_status := 'confirmed',
      p_allow_negative := false
    );

    IF v_restaurant_owner_id IS NOT NULL AND v_restaurant_amount > 0 THEN
      v_restaurant_wallet := public.ensure_user_wallet(v_restaurant_owner_id, 'MZN');
      PERFORM public.apply_wallet_ledger_entry(
        p_wallet_id := v_restaurant_wallet.id,
        p_user_id := v_restaurant_owner_id,
        p_direction := 'credit',
        p_entry_type := 'event_ticket_restaurant_sale',
        p_amount := v_restaurant_amount,
        p_reference_key := 'event_ticket_restaurant:' || v_ticket_id::text,
        p_metadata := jsonb_build_object(
          'event_id', p_event_id,
          'ticket_id', v_ticket_id,
          'ticket_type_id', p_ticket_type_id,
          'ticket_type_name', v_ticket_type_name,
          'buyer_id', p_buyer_id,
          'source', 'deligo_events',
          'merchant_percent', v_merchant_percent
        ),
        p_status := 'confirmed',
        p_allow_negative := true
      );
    END IF;

    IF v_commission > 0 THEN
      IF v_platform_user_id IS NOT NULL THEN
        v_platform_wallet := public.ensure_user_wallet(v_platform_user_id, 'MZN');
        PERFORM public.apply_wallet_ledger_entry(
          p_wallet_id := v_platform_wallet.id,
          p_user_id := v_platform_user_id,
          p_direction := 'credit',
          p_entry_type := 'event_ticket_deligo_commission',
          p_amount := v_commission,
          p_reference_key := 'event_ticket_commission:' || v_ticket_id::text,
          p_metadata := jsonb_build_object(
            'event_id', p_event_id,
            'ticket_id', v_ticket_id,
            'ticket_type_id', p_ticket_type_id,
            'ticket_type_name', v_ticket_type_name,
            'buyer_id', p_buyer_id,
            'source', 'deligo_events',
            'commission_percent', v_platform_percent
          ),
          p_status := 'confirmed',
          p_allow_negative := true
        );
      ELSE
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
            'ticket_type_id', p_ticket_type_id,
            'ticket_type_name', v_ticket_type_name,
            'buyer_id', p_buyer_id,
            'source', 'deligo_events',
            'commission_percent', v_platform_percent
          ),
          p_status := 'confirmed',
          p_allow_negative := true
        );
      END IF;
    END IF;
  END IF;

  IF v_has_ticket_types THEN
    UPDATE public.event_ticket_types
    SET sold = sold + 1,
        status = CASE WHEN sold + 1 >= quantity THEN 'sold_out' ELSE status END
    WHERE id = p_ticket_type_id;
  END IF;

  UPDATE public.marketing_events
  SET tickets_sold = tickets_sold + 1,
      gross_revenue = gross_revenue + v_price,
      deligo_commission = deligo_commission + v_commission,
      net_amount = net_amount + v_restaurant_amount,
      status = CASE
        WHEN sells_tickets IS TRUE
         AND ticket_quantity IS NOT NULL
         AND tickets_sold + 1 >= ticket_quantity THEN 'sold_out'
        ELSE status
      END
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
        'ticket_type_id', p_ticket_type_id,
        'ticket_type_name', v_ticket_type_name,
        'buyer_id', p_buyer_id,
        'gross_amount', v_price,
        'restaurant_amount', v_restaurant_amount,
        'deligo_commission', v_commission,
        'commission_percent', v_platform_percent,
        'source', 'event_ticket_purchase'
      ),
      p_dispatch_key := 'event_ticket_sold:' || v_ticket_id::text || ':' || v_restaurant_owner_id::text
    );
  END IF;

  RETURN v_ticket_id;
END;
$$;
GRANT SELECT ON public.marketing_request_ticket_types TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.marketing_request_ticket_types TO authenticated;
GRANT SELECT ON public.event_ticket_types TO authenticated;
COMMIT;
