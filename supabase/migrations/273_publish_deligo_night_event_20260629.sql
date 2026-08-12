BEGIN;
DO $$
DECLARE
  v_restaurant_id UUID := '311976ef-cc82-45fe-8858-627df6a3c9b7';
  v_owner_id UUID := '32724730-6e08-460a-84f7-34f4074b1988';
  v_request_id UUID;
  v_event_id UUID;
  v_banner_url TEXT := 'https://gfkptccbalpacyypptgl.supabase.co/storage/v1/object/public/restaurant-assets/platform/marketing/events/a-noite-de-deligo-2026-06-29.png';
BEGIN
  SELECT id
  INTO v_request_id
  FROM public.marketing_requests
  WHERE restaurant_id = v_restaurant_id
    AND lower(event_name) = lower('A Noite de DeliGo')
    AND event_date = DATE '2026-06-29'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_request_id IS NULL THEN
    INSERT INTO public.marketing_requests (
      restaurant_id, requested_by, request_type, event_name, description,
      event_date, event_time, event_end_time, location, sells_tickets,
      ticket_price, ticket_quantity, event_category, event_type_detail,
      max_capacity, ticket_options, rules, refund_policy, objective,
      target_audience, age_rating, banner_url, poster_url, sales_start_at,
      sales_end_at, notes, status, restaurant_approved_at, published_at
    ) VALUES (
      v_restaurant_id,
      v_owner_id,
      'theme_party',
      'A Noite de DeliGo',
      'Uma noite especial no Restaurante de DeliGo, com musica, gastronomia e entretenimento num ambiente preparado para celebrar com amigos e familia.',
      DATE '2026-06-29',
      TIME '18:00:00',
      TIME '23:00:00',
      'Edificio Jose Antunes, 25 de Setembro, Maputo',
      true,
      500.00,
      300,
      'festas',
      'Festa Tematica',
      300,
      '[{"name":"Normal","price":500,"quantity":300}]'::jsonb,
      'Apresente o QR Code na entrada. O bilhete e pessoal e permite uma unica entrada. Respeite as orientacoes da organizacao.',
      'Reembolso disponivel ate ao encerramento das vendas. Depois das 17:30 de 29/06/2026, apenas em caso de cancelamento do evento.',
      'increase_sales',
      'all',
      'free',
      v_banner_url,
      v_banner_url,
      TIMESTAMPTZ '2026-06-28 00:00:00+02',
      TIMESTAMPTZ '2026-06-29 17:30:00+02',
      'Evento criado e publicado pela equipa DeliGo.',
      'published',
      now(),
      now()
    )
    RETURNING id INTO v_request_id;
  ELSE
    UPDATE public.marketing_requests
    SET description = 'Uma noite especial no Restaurante de DeliGo, com musica, gastronomia e entretenimento num ambiente preparado para celebrar com amigos e familia.',
        event_time = TIME '18:00:00',
        event_end_time = TIME '23:00:00',
        location = 'Edificio Jose Antunes, 25 de Setembro, Maputo',
        sells_tickets = true,
        ticket_price = 500.00,
        ticket_quantity = 300,
        max_capacity = 300,
        ticket_options = '[{"name":"Normal","price":500,"quantity":300}]'::jsonb,
        banner_url = v_banner_url,
        poster_url = v_banner_url,
        sales_start_at = TIMESTAMPTZ '2026-06-28 00:00:00+02',
        sales_end_at = TIMESTAMPTZ '2026-06-29 17:30:00+02',
        status = 'published',
        published_at = COALESCE(published_at, now()),
        updated_at = now()
    WHERE id = v_request_id;
  END IF;

  INSERT INTO public.marketing_events (
    request_id, restaurant_id, title, description, event_type,
    event_category, event_type_detail, event_date, event_time, event_end_time,
    location, max_capacity, poster_url, banner_url, sells_tickets,
    ticket_price, ticket_quantity, ticket_options, rules, refund_policy,
    sales_start_at, sales_end_at, status, published_at
  ) VALUES (
    v_request_id,
    v_restaurant_id,
    'A Noite de DeliGo',
    'Uma noite especial no Restaurante de DeliGo, com musica, gastronomia e entretenimento num ambiente preparado para celebrar com amigos e familia.',
    'theme_party',
    'festas',
    'Festa Tematica',
    DATE '2026-06-29',
    TIME '18:00:00',
    TIME '23:00:00',
    'Edificio Jose Antunes, 25 de Setembro, Maputo',
    300,
    v_banner_url,
    v_banner_url,
    true,
    500.00,
    300,
    '[]'::jsonb,
    'Apresente o QR Code na entrada. O bilhete e pessoal e permite uma unica entrada. Respeite as orientacoes da organizacao.',
    'Reembolso disponivel ate ao encerramento das vendas. Depois das 17:30 de 29/06/2026, apenas em caso de cancelamento do evento.',
    TIMESTAMPTZ '2026-06-28 00:00:00+02',
    TIMESTAMPTZ '2026-06-29 17:30:00+02',
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
    rules = EXCLUDED.rules,
    refund_policy = EXCLUDED.refund_policy,
    sales_start_at = EXCLUDED.sales_start_at,
    sales_end_at = EXCLUDED.sales_end_at,
    status = 'published',
    updated_at = now()
  RETURNING id INTO v_event_id;

  INSERT INTO public.event_ticket_types (
    event_id, ticket_name, price, quantity, sold, status
  ) VALUES (
    v_event_id, 'Normal', 500.00, 300, 0, 'active'
  )
  ON CONFLICT (event_id, ticket_name) DO UPDATE SET
    price = EXCLUDED.price,
    quantity = GREATEST(public.event_ticket_types.sold, EXCLUDED.quantity),
    status = CASE
      WHEN public.event_ticket_types.sold >= EXCLUDED.quantity THEN 'sold_out'
      ELSE 'active'
    END;

  INSERT INTO public.restaurant_event_wallets (restaurant_id, event_id)
  VALUES (v_restaurant_id, v_event_id)
  ON CONFLICT (restaurant_id, event_id) DO NOTHING;

  INSERT INTO public.marketing_event_metrics (event_id)
  VALUES (v_event_id)
  ON CONFLICT (event_id) DO NOTHING;
END;
$$;
COMMIT;
