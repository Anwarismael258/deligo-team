BEGIN;
CREATE TABLE IF NOT EXISTS public.commission_rules (
  type TEXT PRIMARY KEY,
  platform_percent NUMERIC(5,2) NOT NULL DEFAULT 0,
  merchant_percent NUMERIC(5,2) NOT NULL DEFAULT 100,
  currency TEXT NOT NULL DEFAULT 'MZN',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (platform_percent >= 0 AND platform_percent <= 100),
  CHECK (merchant_percent >= 0 AND merchant_percent <= 100),
  CHECK (round((platform_percent + merchant_percent)::numeric, 2) = 100)
);
INSERT INTO public.commission_rules (
  type,
  platform_percent,
  merchant_percent,
  currency,
  active,
  metadata
)
VALUES (
  'event_ticket',
  10,
  90,
  'MZN',
  TRUE,
  jsonb_build_object('description', 'Bilhetes DeliGo Eventos')
)
ON CONFLICT (type) DO UPDATE SET
  platform_percent = EXCLUDED.platform_percent,
  merchant_percent = EXCLUDED.merchant_percent,
  currency = EXCLUDED.currency,
  active = TRUE,
  updated_at = now();
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
  v_buyer_wallet public.wallets%ROWTYPE;
  v_restaurant_wallet public.wallets%ROWTYPE;
  v_platform_wallet public.wallets%ROWTYPE;
  v_commission NUMERIC(12,2);
  v_restaurant_amount NUMERIC(12,2);
  v_price NUMERIC(12,2);
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

  IF v_event.ticket_quantity IS NOT NULL AND v_event.tickets_sold >= v_event.ticket_quantity THEN
    RAISE EXCEPTION 'event_sold_out';
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
  v_price := COALESCE(v_event.ticket_price, 0);
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
      p_wallet_id := v_buyer_wallet.id,
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
        'commission_percent', v_platform_percent,
        'source', 'event_ticket_purchase'
      ),
      p_dispatch_key := 'event_ticket_sold:' || v_ticket_id::text || ':' || v_restaurant_owner_id::text
    );
  END IF;

  RETURN v_ticket_id;
END;
$$;
CREATE OR REPLACE VIEW public.admin_event_ticket_financial_summary AS
SELECT
  count(*) FILTER (WHERE t.status IN ('sold', 'used')) AS tickets_sold,
  COALESCE(sum(t.price) FILTER (WHERE t.status IN ('sold', 'used')), 0) AS gross_amount,
  COALESCE(sum(t.deligo_commission) FILTER (WHERE t.status IN ('sold', 'used')), 0) AS deligo_commission,
  COALESCE(sum(t.restaurant_amount) FILTER (WHERE t.status IN ('sold', 'used')), 0) AS restaurant_net_amount,
  COALESCE(sum(t.price) FILTER (WHERE t.sold_at::date = current_date), 0) AS gross_today,
  COALESCE(sum(t.deligo_commission) FILTER (WHERE t.sold_at::date = current_date), 0) AS commission_today,
  COALESCE(sum(t.deligo_commission) FILTER (WHERE t.sold_at >= date_trunc('week', now())), 0) AS commission_week,
  COALESCE(sum(t.deligo_commission) FILTER (WHERE t.sold_at >= date_trunc('month', now())), 0) AS commission_month
FROM public.marketing_event_tickets t
WHERE public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']);
CREATE OR REPLACE VIEW public.restaurant_event_ticket_financial_summary AS
SELECT
  e.restaurant_id,
  e.id AS event_id,
  e.title,
  e.ticket_quantity,
  e.tickets_sold,
  e.tickets_used,
  GREATEST(COALESCE(e.ticket_quantity, 0) - COALESCE(e.tickets_sold, 0), 0) AS seats_available,
  e.gross_revenue,
  e.deligo_commission,
  e.net_amount,
  e.status,
  e.event_date,
  e.event_time
FROM public.marketing_events e
JOIN public.restaurants r ON r.id = e.restaurant_id
WHERE r.owner_id = auth.uid()
   OR public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']);
GRANT SELECT ON public.admin_event_ticket_financial_summary TO authenticated;
GRANT SELECT ON public.restaurant_event_ticket_financial_summary TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.commission_rules TO service_role;
GRANT SELECT ON public.commission_rules TO authenticated;
GRANT EXECUTE ON FUNCTION public.sell_marketing_event_ticket(UUID, UUID) TO authenticated;
COMMIT;
