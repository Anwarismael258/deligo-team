BEGIN;
CREATE OR REPLACE FUNCTION public.process_delivery_completion_settlement(
  p_order_id UUID,
  p_customer_id UUID,
  p_platform_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%rowtype;
  v_split RECORD;
  v_result JSONB;
  v_delivered_at TIMESTAMPTZ;
BEGIN
  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND COALESCE(client_id, customer_id) = p_customer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF v_order.status = 'disputed' THEN
    RAISE EXCEPTION 'order_in_dispute';
  END IF;

  IF v_order.status IN ('completed', 'auto_completed') THEN
    RETURN jsonb_build_object(
      'success', true,
      'duplicate', true,
      'status', v_order.status
    );
  END IF;

  SELECT id, status
  INTO v_split
  FROM public.payment_splits
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF FOUND AND COALESCE(v_split.status, '') = 'completed' THEN
    RETURN jsonb_build_object(
      'success', true,
      'duplicate', true,
      'status', 'completed'
    );
  END IF;

  IF v_order.status = 'delivered' THEN
    v_delivered_at := COALESCE(v_order.delivered_at, NOW());

    UPDATE public.orders
    SET status = 'arrived',
        updated_at = NOW()
    WHERE id = p_order_id
      AND status = 'delivered';

    BEGIN
      v_result := public.process_delivery_settlement(
        p_order_id := p_order_id,
        p_customer_id := p_customer_id,
        p_platform_user_id := p_platform_user_id
      );
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.orders
      SET status = 'delivered',
          delivered_at = COALESCE(delivered_at, v_delivered_at),
          updated_at = NOW()
      WHERE id = p_order_id;
      RAISE;
    END;

    UPDATE public.orders
    SET status = 'delivered',
        delivered_at = COALESCE(delivered_at, v_delivered_at),
        updated_at = NOW()
    WHERE id = p_order_id;

    RETURN COALESCE(v_result, '{}'::jsonb) || jsonb_build_object(
      'status', 'delivered',
      'settlement_mode', 'delivery_completion'
    );
  END IF;

  IF v_order.status NOT IN ('in_transit', 'arrived', 'on_the_way', 'courier_assigned', 'ready') THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  RETURN public.process_delivery_settlement(
    p_order_id := p_order_id,
    p_customer_id := p_customer_id,
    p_platform_user_id := p_platform_user_id
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.process_stuck_orders(
  p_platform_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_restaurant_timeouts INTEGER := 0;
  v_courier_reassignments INTEGER := 0;
  v_late_flags INTEGER := 0;
  v_refunds INTEGER := 0;
  v_pickup_auto_completions INTEGER := 0;
  v_delivery_auto_completions INTEGER := 0;
  v_order RECORD;
  v_user_id UUID;
  v_cancel_result JSONB;
  v_restaurant_owner UUID;
BEGIN
  FOR v_order IN
    SELECT o.id, o.status, o.client_id, o.customer_id
    FROM public.orders o
    WHERE (
      o.status IN ('paid', 'payment_authorized')
      AND COALESCE(o.updated_at, o.created_at) <= NOW() - INTERVAL '3 minutes'
    ) OR (
      o.status = 'pending'
      AND COALESCE(o.payment_status, 'pending') IN ('paid', 'completed', 'authorized')
      AND COALESCE(o.updated_at, o.created_at) <= NOW() - INTERVAL '3 minutes'
    ) OR (
      o.status = 'pending'
      AND COALESCE(o.payment_status, 'pending') NOT IN ('paid', 'completed', 'authorized')
      AND o.created_at <= NOW() - INTERVAL '15 minutes'
    )
  LOOP
    v_user_id := COALESCE(v_order.client_id, v_order.customer_id);
    IF v_user_id IS NULL THEN
      CONTINUE;
    END IF;

    BEGIN
      v_cancel_result := public.process_order_cancellation(
        p_order_id := v_order.id,
        p_user_id := v_user_id,
        p_reason := 'restaurant_timeout'
      );

      v_restaurant_timeouts := v_restaurant_timeouts + 1;
      IF COALESCE((v_cancel_result ->> 'refund_amount')::NUMERIC, 0) > 0 THEN
        v_refunds := v_refunds + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.order_events (
        order_id,
        event_type,
        old_status,
        new_status,
        metadata
      ) VALUES (
        v_order.id,
        'restaurant_timeout_cancel_failed',
        v_order.status,
        v_order.status,
        jsonb_build_object(
          'auto', true,
          'source', 'process_stuck_orders',
          'error', SQLERRM
        )
      );
    END;
  END LOOP;

  FOR v_order IN
    SELECT o.*
    FROM public.orders o
    WHERE COALESCE(
            NULLIF(o.delivery_type, ''),
            CASE WHEN COALESCE(o.delivery_fee, 0) > 0 THEN 'delivery' ELSE 'pickup' END
          ) = 'pickup'
      AND o.status = 'ready'
      AND COALESCE(o.payment_status, 'pending') IN ('authorized', 'paid', 'completed')
      AND COALESCE(o.confirmed_by_customer, FALSE) = FALSE
      AND COALESCE(o.client_id, o.customer_id) IS NOT NULL
      AND COALESCE(o.ready_at, o.updated_at, o.created_at) <= NOW() - INTERVAL '20 minutes'
  LOOP
    BEGIN
      PERFORM public.process_delivery_completion_settlement(
        p_order_id := v_order.id,
        p_customer_id := COALESCE(v_order.client_id, v_order.customer_id),
        p_platform_user_id := p_platform_user_id
      );

      UPDATE public.orders
      SET status = 'auto_completed',
          order_completed_at = COALESCE(order_completed_at, NOW()),
          settlement_processed_at = COALESCE(settlement_processed_at, NOW()),
          updated_at = NOW()
      WHERE id = v_order.id
        AND status = 'ready';

      IF FOUND THEN
        INSERT INTO public.order_events (
          order_id,
          event_type,
          old_status,
          new_status,
          metadata
        ) VALUES (
          v_order.id,
          'pickup_auto_completed',
          'ready',
          'auto_completed',
          jsonb_build_object(
            'auto', true,
            'source', 'process_stuck_orders',
            'timeout_minutes', 20
          )
        );

        v_pickup_auto_completions := v_pickup_auto_completions + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.order_events (
        order_id,
        event_type,
        old_status,
        new_status,
        metadata
      ) VALUES (
        v_order.id,
        'pickup_auto_complete_failed',
        v_order.status,
        v_order.status,
        jsonb_build_object(
          'auto', true,
          'source', 'process_stuck_orders',
          'timeout_minutes', 20,
          'error', SQLERRM
        )
      );
    END;
  END LOOP;

  FOR v_order IN
    SELECT o.*
    FROM public.orders o
    WHERE COALESCE(
            NULLIF(o.delivery_type, ''),
            CASE WHEN COALESCE(o.delivery_fee, 0) > 0 THEN 'delivery' ELSE 'pickup' END
          ) = 'delivery'
      AND o.status = 'delivered'
      AND COALESCE(o.confirmed_by_customer, FALSE) = FALSE
      AND COALESCE(o.client_id, o.customer_id) IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.order_disputes od
        WHERE od.order_id = o.id
          AND COALESCE(od.status, 'open') = 'open'
      )
      AND COALESCE(
            o.delivery_extension_until,
            COALESCE(o.delivered_at, o.updated_at, o.created_at) + INTERVAL '10 minutes'
          ) <= NOW()
  LOOP
    BEGIN
      PERFORM public.process_delivery_completion_settlement(
        p_order_id := v_order.id,
        p_customer_id := COALESCE(v_order.client_id, v_order.customer_id),
        p_platform_user_id := p_platform_user_id
      );

      UPDATE public.orders
      SET status = 'auto_completed',
          order_completed_at = COALESCE(order_completed_at, NOW()),
          settlement_processed_at = COALESCE(settlement_processed_at, NOW()),
          updated_at = NOW()
      WHERE id = v_order.id
        AND status = 'delivered';

      IF FOUND THEN
        INSERT INTO public.order_events (
          order_id,
          event_type,
          old_status,
          new_status,
          metadata
        ) VALUES (
          v_order.id,
          'delivery_auto_completed',
          'delivered',
          'auto_completed',
          jsonb_build_object(
            'auto', true,
            'source', 'process_stuck_orders',
            'timeout_minutes', 10,
            'extension_until', v_order.delivery_extension_until,
            'extension_count', COALESCE(v_order.delivery_extension_count, 0)
          )
        );

        SELECT r.owner_id
        INTO v_restaurant_owner
        FROM public.restaurants r
        WHERE r.id = v_order.restaurant_id
        LIMIT 1;

        IF COALESCE(v_order.client_id, v_order.customer_id) IS NOT NULL THEN
          PERFORM public.create_app_notification(
            p_user_id := COALESCE(v_order.client_id, v_order.customer_id),
            p_type := 'ORDER_AUTO_COMPLETED',
            p_title := 'Pedido concluido automaticamente',
            p_body := 'Como nao houve confirmacao nem problema reportado dentro da janela, o pedido foi concluido automaticamente.',
            p_action := 'OPEN_ORDER',
            p_entity_id := v_order.id::TEXT,
            p_priority := 'HIGH',
            p_channel := 'delivery',
            p_metadata := jsonb_build_object(
              'order_id', v_order.id,
              'status', 'auto_completed'
            )
          );
        END IF;

        IF v_restaurant_owner IS NOT NULL THEN
          PERFORM public.create_app_notification(
            p_user_id := v_restaurant_owner,
            p_type := 'ORDER_AUTO_COMPLETED',
            p_title := 'Entrega fechada automaticamente',
            p_body := 'O pedido foi concluido automaticamente apos a janela de confirmacao do cliente.',
            p_action := 'OPEN_ORDER',
            p_entity_id := v_order.id::TEXT,
            p_priority := 'MEDIUM',
            p_channel := 'restaurant',
            p_metadata := jsonb_build_object(
              'order_id', v_order.id,
              'status', 'auto_completed'
            )
          );
        END IF;

        v_delivery_auto_completions := v_delivery_auto_completions + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.order_events (
        order_id,
        event_type,
        old_status,
        new_status,
        metadata
      ) VALUES (
        v_order.id,
        'delivery_auto_complete_failed',
        v_order.status,
        v_order.status,
        jsonb_build_object(
          'auto', true,
          'source', 'process_stuck_orders',
          'timeout_minutes', 10,
          'error', SQLERRM
        )
      );
    END;
  END LOOP;

  FOR v_order IN
    SELECT *
    FROM public.orders
    WHERE courier_id IS NOT NULL
      AND status = 'courier_assigned'
      AND updated_at < NOW() - INTERVAL '20 minutes'
  LOOP
    PERFORM public.register_courier_incident(
      v_order.courier_id,
      'offline_after_accept',
      v_order.id,
      25,
      'high',
      jsonb_build_object(
        'source', 'stuck_order_sweep',
        'reason', 'no_movement_after_assignment'
      )
    );

    UPDATE public.orders
    SET courier_id = NULL,
        status = 'ready',
        updated_at = NOW()
    WHERE id = v_order.id;

    INSERT INTO public.order_events (
      order_id,
      event_type,
      old_status,
      new_status,
      metadata
    ) VALUES (
      v_order.id,
      'courier_reassignment_requested',
      'courier_assigned',
      'ready',
      jsonb_build_object(
        'previous_courier_id', v_order.courier_id,
        'auto', true
      )
    );

    v_courier_reassignments := v_courier_reassignments + 1;
  END LOOP;

  FOR v_order IN
    SELECT *
    FROM public.orders
    WHERE courier_id IS NOT NULL
      AND status IN ('in_transit', 'arrived')
      AND updated_at < NOW() - INTERVAL '60 minutes'
  LOOP
    PERFORM public.register_courier_incident(
      v_order.courier_id,
      'late_delivery',
      v_order.id,
      12,
      'medium',
      jsonb_build_object(
        'source', 'stuck_order_sweep',
        'reason', 'transit_sla_exceeded'
      )
    );

    INSERT INTO public.order_events (
      order_id,
      event_type,
      old_status,
      new_status,
      metadata
    ) VALUES (
      v_order.id,
      'delivery_sla_exceeded',
      v_order.status,
      v_order.status,
      jsonb_build_object(
        'courier_id', v_order.courier_id,
        'auto', true
      )
    );

    v_late_flags := v_late_flags + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'restaurant_timeouts', v_restaurant_timeouts,
    'pickup_auto_completions', v_pickup_auto_completions,
    'delivery_auto_completions', v_delivery_auto_completions,
    'courier_reassignments', v_courier_reassignments,
    'late_flags', v_late_flags,
    'refunds', v_refunds
  );
END;
$$;
DROP VIEW IF EXISTS public.restaurant_sla_metrics;
CREATE VIEW public.restaurant_sla_metrics AS
WITH recent_orders AS (
  SELECT o.*
  FROM public.orders o
  WHERE o.created_at >= NOW() - INTERVAL '30 days'
)
SELECT
  r.id AS restaurant_id,
  r.owner_id,
  r.name AS restaurant_name,
  COUNT(o.id) AS total_orders_30d,
  COUNT(o.id) FILTER (WHERE o.accepted_at IS NOT NULL) AS accepted_orders_30d,
  COUNT(o.id) FILTER (WHERE o.status IN ('completed', 'auto_completed')) AS completed_orders_30d,
  COUNT(o.id) FILTER (WHERE o.status = 'auto_completed') AS auto_completed_orders_30d,
  COUNT(o.id) FILTER (WHERE o.status = 'cancelled') AS cancelled_orders_30d,
  COUNT(o.id) FILTER (WHERE o.status = 'disputed') AS disputed_orders_30d,
  ROUND((AVG(EXTRACT(EPOCH FROM (o.accepted_at - o.created_at))) FILTER (WHERE o.accepted_at IS NOT NULL))::NUMERIC, 2)
    AS avg_accept_seconds_30d,
  ROUND((AVG(EXTRACT(EPOCH FROM (o.ready_at - COALESCE(o.preparing_at, o.accepted_at)))) FILTER (
    WHERE o.ready_at IS NOT NULL
      AND COALESCE(o.preparing_at, o.accepted_at) IS NOT NULL
  ))::NUMERIC, 2) AS avg_prep_seconds_30d,
  ROUND((AVG(EXTRACT(EPOCH FROM (o.picked_up_at - o.ready_at))) FILTER (
    WHERE o.picked_up_at IS NOT NULL
      AND o.ready_at IS NOT NULL
  ))::NUMERIC, 2) AS avg_ready_to_pickup_seconds_30d,
  ROUND((AVG(EXTRACT(EPOCH FROM (o.delivered_at - o.picked_up_at))) FILTER (
    WHERE o.delivered_at IS NOT NULL
      AND o.picked_up_at IS NOT NULL
  ))::NUMERIC, 2) AS avg_delivery_seconds_30d,
  ROUND((AVG(EXTRACT(EPOCH FROM (COALESCE(o.order_completed_at, o.delivered_at, o.updated_at) - o.created_at))) FILTER (
    WHERE o.status IN ('completed', 'auto_completed')
  ))::NUMERIC, 2) AS avg_total_seconds_30d,
  COUNT(o.id) FILTER (
    WHERE o.accepted_at IS NOT NULL
      AND o.accepted_at <= o.created_at + INTERVAL '3 minutes'
  ) AS on_time_accept_orders_30d,
  COUNT(o.id) FILTER (
    WHERE o.ready_at IS NOT NULL
      AND COALESCE(o.preparing_at, o.accepted_at, o.created_at) IS NOT NULL
      AND o.ready_at <= COALESCE(o.preparing_at, o.accepted_at, o.created_at)
          + make_interval(mins => GREATEST(COALESCE(o.estimated_delivery_time, 25), 1))
  ) AS on_time_prep_orders_30d,
  ROUND((
    (COUNT(o.id) FILTER (
      WHERE o.accepted_at IS NOT NULL
        AND o.accepted_at <= o.created_at + INTERVAL '3 minutes'
    ))::NUMERIC
    / NULLIF(COUNT(o.id) FILTER (WHERE o.accepted_at IS NOT NULL), 0)
  ) * 100, 2) AS accept_sla_rate_30d,
  ROUND((
    (COUNT(o.id) FILTER (
      WHERE o.ready_at IS NOT NULL
        AND COALESCE(o.preparing_at, o.accepted_at, o.created_at) IS NOT NULL
        AND o.ready_at <= COALESCE(o.preparing_at, o.accepted_at, o.created_at)
            + make_interval(mins => GREATEST(COALESCE(o.estimated_delivery_time, 25), 1))
    ))::NUMERIC
    / NULLIF(COUNT(o.id) FILTER (WHERE o.ready_at IS NOT NULL), 0)
  ) * 100, 2) AS prep_sla_rate_30d,
  ROUND((
    (COUNT(o.id) FILTER (WHERE o.status IN ('completed', 'auto_completed')))::NUMERIC
    / NULLIF(COUNT(o.id), 0)
  ) * 100, 2) AS completion_rate_30d,
  ROUND((
    COALESCE((
      (COUNT(o.id) FILTER (
        WHERE o.accepted_at IS NOT NULL
          AND o.accepted_at <= o.created_at + INTERVAL '3 minutes'
      ))::NUMERIC
      / NULLIF(COUNT(o.id) FILTER (WHERE o.accepted_at IS NOT NULL), 0)
    ) * 100, 0)
    + COALESCE((
      (COUNT(o.id) FILTER (
        WHERE o.ready_at IS NOT NULL
          AND COALESCE(o.preparing_at, o.accepted_at, o.created_at) IS NOT NULL
          AND o.ready_at <= COALESCE(o.preparing_at, o.accepted_at, o.created_at)
              + make_interval(mins => GREATEST(COALESCE(o.estimated_delivery_time, 25), 1))
      ))::NUMERIC
      / NULLIF(COUNT(o.id) FILTER (WHERE o.ready_at IS NOT NULL), 0)
    ) * 100, 0)
    + COALESCE((
      (COUNT(o.id) FILTER (WHERE o.status IN ('completed', 'auto_completed')))::NUMERIC
      / NULLIF(COUNT(o.id), 0)
    ) * 100, 0)
  ) / 3, 2) AS sla_score_30d
FROM public.restaurants r
LEFT JOIN recent_orders o ON o.restaurant_id = r.id
GROUP BY r.id, r.owner_id, r.name;
COMMIT;
