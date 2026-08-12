-- Ensure automatic ready transition uses the order-specific prep window.

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
BEGIN
  FOR v_order IN
    SELECT
      o.id,
      o.status,
      o.updated_at,
      o.created_at,
      o.preparation_started_at,
      o.estimated_delivery_time,
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
    v_started_at := COALESCE(
      v_order.preparation_started_at,
      v_order.restaurant_confirmed_at,
      v_order.updated_at,
      v_order.created_at
    );
    v_prep_minutes := GREATEST(
      COALESCE(v_order.estimated_delivery_time, v_order.restaurant_prep_minutes, 25),
      1
    );

    IF v_order.status = 'accepted'
       AND v_started_at <= NOW() - INTERVAL '1 minute' THEN
      UPDATE public.orders
      SET status = 'preparing',
          updated_at = NOW()
      WHERE id = v_order.id
        AND status = 'accepted';

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
    ELSIF v_started_at + make_interval(mins => v_prep_minutes) <= NOW() THEN
      UPDATE public.orders
      SET status = 'ready',
          updated_at = NOW()
      WHERE id = v_order.id
        AND status IN ('accepted', 'preparing');

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
