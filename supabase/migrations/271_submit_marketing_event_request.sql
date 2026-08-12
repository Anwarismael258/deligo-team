BEGIN;
CREATE OR REPLACE FUNCTION public.submit_marketing_event_request(
  p_payload JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_restaurant_id UUID;
  v_request_id UUID;
  v_sells_tickets BOOLEAN := COALESCE((p_payload->>'sells_tickets')::boolean, false);
  v_tickets JSONB := COALESCE(p_payload->'ticket_options', '[]'::jsonb);
  v_first_ticket JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'session_expired';
  END IF;

  v_restaurant_id := NULLIF(p_payload->>'restaurant_id', '')::uuid;
  IF v_restaurant_id IS NULL OR NOT public.is_restaurant_owner(v_restaurant_id) THEN
    RAISE EXCEPTION 'restaurant_owner_required';
  END IF;

  IF NULLIF(trim(p_payload->>'event_name'), '') IS NULL
     OR NULLIF(trim(p_payload->>'description'), '') IS NULL
     OR NULLIF(trim(p_payload->>'location'), '') IS NULL THEN
    RAISE EXCEPTION 'event_required_fields_missing';
  END IF;

  IF v_sells_tickets AND jsonb_array_length(v_tickets) = 0 THEN
    RAISE EXCEPTION 'ticket_type_required';
  END IF;

  v_first_ticket := v_tickets->0;

  INSERT INTO public.marketing_requests (
    restaurant_id, requested_by, request_type, event_name, description,
    event_date, event_time, event_end_time, location, sells_tickets,
    ticket_price, ticket_quantity, event_category, event_type_detail,
    max_capacity, ticket_options, rules, refund_policy, objective,
    target_audience, age_rating, logo_url, photo_urls, banner_url, poster_url,
    brand_colors, social_links, website, sales_start_at, sales_end_at,
    sla_due_at, notes, status
  ) VALUES (
    v_restaurant_id,
    v_user_id,
    p_payload->>'request_type',
    trim(p_payload->>'event_name'),
    trim(p_payload->>'description'),
    (p_payload->>'event_date')::date,
    (p_payload->>'event_time')::time,
    NULLIF(p_payload->>'event_end_time', '')::time,
    trim(p_payload->>'location'),
    v_sells_tickets,
    CASE WHEN v_sells_tickets THEN (v_first_ticket->>'price')::numeric ELSE NULL END,
    CASE WHEN v_sells_tickets THEN (v_first_ticket->>'quantity')::integer ELSE NULL END,
    NULLIF(trim(p_payload->>'event_category'), ''),
    NULLIF(trim(p_payload->>'event_type_detail'), ''),
    NULLIF(p_payload->>'max_capacity', '')::integer,
    v_tickets,
    NULLIF(trim(p_payload->>'rules'), ''),
    NULLIF(trim(p_payload->>'refund_policy'), ''),
    COALESCE(NULLIF(p_payload->>'objective', ''), 'increase_sales'),
    COALESCE(NULLIF(p_payload->>'target_audience', ''), 'all'),
    COALESCE(NULLIF(p_payload->>'age_rating', ''), 'free'),
    NULLIF(trim(p_payload->>'logo_url'), ''),
    COALESCE(ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_payload->'photo_urls', '[]'::jsonb))), '{}'),
    NULLIF(trim(p_payload->>'banner_url'), ''),
    NULLIF(trim(p_payload->>'banner_url'), ''),
    NULLIF(trim(p_payload->>'brand_colors'), ''),
    NULLIF(trim(p_payload->>'social_links'), ''),
    NULLIF(trim(p_payload->>'website'), ''),
    CASE WHEN v_sells_tickets THEN NULLIF(p_payload->>'sales_start_at', '')::timestamptz ELSE NULL END,
    CASE WHEN v_sells_tickets THEN NULLIF(p_payload->>'sales_end_at', '')::timestamptz ELSE NULL END,
    now() + make_interval(hours => COALESCE(NULLIF(p_payload->>'sla_hours', '')::integer, 48)),
    NULLIF(trim(p_payload->>'notes'), ''),
    'received'
  )
  RETURNING id INTO v_request_id;

  IF v_sells_tickets THEN
    INSERT INTO public.marketing_request_ticket_types (
      request_id, ticket_name, price, quantity, status
    )
    SELECT
      v_request_id,
      trim(item->>'name'),
      (item->>'price')::numeric,
      (item->>'quantity')::integer,
      'active'
    FROM jsonb_array_elements(v_tickets) AS item;
  END IF;

  RETURN v_request_id;
END;
$$;
REVOKE ALL ON FUNCTION public.submit_marketing_event_request(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_marketing_event_request(JSONB) TO authenticated;
COMMIT;
