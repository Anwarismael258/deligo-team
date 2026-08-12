BEGIN;
CREATE OR REPLACE FUNCTION public.process_preparing_orders()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_preparing_count INTEGER := 0;
  v_ready_count INTEGER := 0;
  v_order RECORD;
  v_prep_minutes INTEGER;
  v_started_at TIMESTAMPTZ;
  v_now TIMESTAMPTZ;
BEGIN
  FOR v_order IN
    SELECT
      o.id,
      o.status,
      o.updated_at,
      o.created_at,
      o.estimated_delivery_time,
      o.accepted_at,
      o.preparing_at,
      ps.restaurant_confirmed_at,
      COALESCE(r.estimated_delivery_time, 25) AS restaurant_prep_minutes
    FROM public.orders o
    LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
    LEFT JOIN LATERAL (
      SELECT p.restaurant_confirmed_at
      FROM public.payment_splits p
      WHERE p.order_id = o.id
      ORDER BY p.created_at DESC NULLS LAST
      LIMIT 1
    ) ps ON TRUE
    WHERE o.status IN ('accepted', 'preparing')
  LOOP
    v_now := NOW();
    v_started_at := COALESCE(
      v_order.preparing_at,
      v_order.accepted_at,
      v_order.restaurant_confirmed_at,
      v_order.updated_at,
      v_order.created_at
    );
    v_prep_minutes := GREATEST(
      COALESCE(v_order.estimated_delivery_time, v_order.restaurant_prep_minutes, 25),
      1
    );

    IF v_order.status = 'accepted'
       AND v_started_at <= v_now - INTERVAL '1 minute' THEN
      UPDATE public.orders
      SET status = 'preparing',
          preparing_at = COALESCE(preparing_at, v_now),
          updated_at = v_now
      WHERE id = v_order.id
        AND status = 'accepted';

      IF FOUND THEN
        INSERT INTO public.order_events (
          order_id,
          event_type,
          old_status,
          new_status,
          metadata
        ) VALUES (
          v_order.id,
          'status_changed',
          'accepted',
          'preparing',
          jsonb_build_object(
            'auto', true,
            'source', 'process_preparing_orders',
            'prep_minutes', v_prep_minutes
          )
        );
        v_preparing_count := v_preparing_count + 1;
      END IF;
    ELSIF v_started_at + make_interval(mins => v_prep_minutes) <= v_now THEN
      UPDATE public.orders
      SET status = 'ready',
          preparing_at = COALESCE(preparing_at, v_started_at),
          ready_at = COALESCE(ready_at, v_now),
          updated_at = v_now
      WHERE id = v_order.id
        AND status IN ('accepted', 'preparing');

      IF FOUND THEN
        INSERT INTO public.order_events (
          order_id,
          event_type,
          old_status,
          new_status,
          metadata
        ) VALUES (
          v_order.id,
          'status_changed',
          v_order.status,
          'ready',
          jsonb_build_object(
            'auto', true,
            'source', 'process_preparing_orders',
            'prep_minutes', v_prep_minutes,
            'started_at', v_started_at
          )
        );
        v_ready_count := v_ready_count + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'moved_to_preparing', v_preparing_count,
    'moved_to_ready', v_ready_count
  );
END;
$$;
REVOKE ALL ON FUNCTION public.process_preparing_orders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_preparing_orders() TO authenticated;
CREATE OR REPLACE FUNCTION public.restaurant_update_order_status(
  p_order_id UUID,
  p_status TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_allowed BOOLEAN := FALSE;
  v_order public.orders%rowtype;
  v_previous_status TEXT;
  v_normalized_status TEXT := LOWER(COALESCE(btrim(p_status), ''));
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  IF v_normalized_status = '' THEN
    RAISE EXCEPTION 'status_required';
  END IF;

  SELECT o.*
  INTO v_order
  FROM public.orders o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.restaurants r
    WHERE r.id = v_order.restaurant_id
      AND r.owner_id = v_user_id
  )
  INTO v_allowed;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'restaurant_not_authorized';
  END IF;

  IF v_normalized_status NOT IN ('accepted', 'preparing', 'ready', 'cancelled') THEN
    RAISE EXCEPTION 'invalid_restaurant_status';
  END IF;

  IF NOT public.validate_order_transition(
    COALESCE(v_order.status, ''),
    v_normalized_status,
    COALESCE(v_order.delivery_type, CASE WHEN COALESCE(v_order.delivery_fee, 0) > 0 THEN 'delivery' ELSE 'pickup' END)
  ) THEN
    RAISE EXCEPTION 'invalid_order_transition';
  END IF;

  IF v_normalized_status = 'accepted'
     AND COALESCE(v_order.payment_status, 'pending') NOT IN ('authorized', 'completed', 'paid') THEN
    RAISE EXCEPTION 'payment_not_authorized';
  END IF;

  v_previous_status := v_order.status;

  BEGIN
    EXECUTE 'ALTER TABLE public.orders DISABLE TRIGGER USER';
    UPDATE public.orders
    SET status = v_normalized_status,
        accepted_at = CASE WHEN v_normalized_status = 'accepted' THEN COALESCE(accepted_at, v_now) ELSE accepted_at END,
        preparing_at = CASE WHEN v_normalized_status = 'preparing' THEN COALESCE(preparing_at, v_now) ELSE preparing_at END,
        ready_at = CASE WHEN v_normalized_status = 'ready' THEN COALESCE(ready_at, v_now) ELSE ready_at END,
        updated_at = v_now
    WHERE id = p_order_id
      AND status = v_previous_status
    RETURNING * INTO v_order;
    EXECUTE 'ALTER TABLE public.orders ENABLE TRIGGER USER';
  EXCEPTION WHEN OTHERS THEN
    EXECUTE 'ALTER TABLE public.orders ENABLE TRIGGER USER';
    RAISE;
  END;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'concurrent_order_transition';
  END IF;

  IF v_normalized_status = 'accepted' AND COALESCE(v_previous_status, '') <> 'accepted' THEN
    UPDATE public.payment_splits
    SET status = CASE WHEN status = 'escrowed' THEN 'restaurant_confirmed' ELSE status END,
        restaurant_confirmed_at = COALESCE(restaurant_confirmed_at, v_now)
    WHERE order_id = p_order_id;
  END IF;

  INSERT INTO public.order_events (
    order_id,
    event_type,
    old_status,
    new_status,
    metadata
  ) VALUES (
    p_order_id,
    'status_changed',
    v_previous_status,
    v_normalized_status,
    jsonb_build_object(
      'payment_status', v_order.payment_status,
      'funds_status', v_order.funds_status,
      'source', 'restaurant_update_order_status',
      'restaurant_user_id', v_user_id,
      'accepted_at', v_order.accepted_at,
      'preparing_at', v_order.preparing_at,
      'ready_at', v_order.ready_at
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order.id,
    'status', v_order.status,
    'updated_at', v_order.updated_at,
    'delivery_type', v_order.delivery_type,
    'delivery_fee', v_order.delivery_fee,
    'payment_status', v_order.payment_status,
    'funds_status', v_order.funds_status,
    'accepted_at', v_order.accepted_at,
    'preparing_at', v_order.preparing_at,
    'ready_at', v_order.ready_at
  );
END;
$$;
COMMIT;
