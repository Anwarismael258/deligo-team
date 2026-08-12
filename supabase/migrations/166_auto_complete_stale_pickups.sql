BEGIN;
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
  v_pickup_completions INTEGER := 0;
  v_order RECORD;
BEGIN
  FOR v_order IN
    SELECT *
    FROM public.orders
    WHERE (
        (status = 'pending' AND created_at < NOW() - INTERVAL '15 minutes')
        OR (status = 'paid' AND created_at < NOW() - INTERVAL '180 seconds')
      )
      AND COALESCE(payment_status, 'pending') IN ('pending', 'completed')
  LOOP
    IF v_order.payment_status = 'completed' THEN
      PERFORM public.apply_wallet_ledger_entry(
        p_wallet_id := (
          SELECT id
          FROM public.wallets
          WHERE user_id = COALESCE(v_order.client_id, v_order.customer_id)
          LIMIT 1
        ),
        p_user_id := COALESCE(v_order.client_id, v_order.customer_id),
        p_order_id := v_order.id,
        p_direction := 'credit',
        p_entry_type := 'order_timeout_refund',
        p_amount := COALESCE(v_order.total_amount, 0),
        p_reference_key := 'order-timeout-refund-' || v_order.id::text,
        p_metadata := jsonb_build_object(
          'reason', 'restaurant_timeout',
          'timeout_seconds', CASE WHEN v_order.status = 'paid' THEN 180 ELSE 900 END
        ),
        p_status := 'confirmed'
      );
      v_refunds := v_refunds + 1;
    END IF;

    UPDATE public.orders
    SET status = 'cancelled',
        payment_status = CASE
          WHEN payment_status = 'completed' THEN 'refunded'
          ELSE payment_status
        END,
        updated_at = NOW()
    WHERE id = v_order.id;

    UPDATE public.payment_splits
    SET status = 'cancelled'
    WHERE order_id = v_order.id;

    INSERT INTO public.order_events (
      order_id,
      event_type,
      old_status,
      new_status,
      metadata
    ) VALUES (
      v_order.id,
      'restaurant_timeout_cancelled',
      v_order.status,
      'cancelled',
      jsonb_build_object(
        'auto', true,
        'timeout_seconds', CASE WHEN v_order.status = 'paid' THEN 180 ELSE 900 END
      )
    );

    v_restaurant_timeouts := v_restaurant_timeouts + 1;
  END LOOP;

  FOR v_order IN
    SELECT o.*
    FROM public.orders o
    WHERE COALESCE(o.delivery_type, '') = 'pickup'
      AND COALESCE(o.delivery_fee, 0) <= 0
      AND o.status IN ('accepted', 'preparing', 'ready')
      AND COALESCE(o.payment_status, 'pending') IN ('paid', 'completed')
      AND COALESCE(o.confirmed_by_customer, FALSE) = FALSE
      AND COALESCE(
        (
          SELECT p.restaurant_confirmed_at
          FROM public.payment_splits p
          WHERE p.order_id = o.id
          ORDER BY p.created_at DESC NULLS LAST
          LIMIT 1
        ),
        o.updated_at,
        o.created_at
      ) + make_interval(
        mins => GREATEST(COALESCE(o.estimated_delivery_time, 25), 1)
      ) <= NOW()
  LOOP
    UPDATE public.orders
    SET status = 'completed',
        confirmed_by_customer = TRUE,
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
      'pickup_auto_completed',
      v_order.status,
      'completed',
      jsonb_build_object(
        'auto', true,
        'source', 'process_stuck_orders',
        'estimated_delivery_time', COALESCE(v_order.estimated_delivery_time, 25)
      )
    );

    v_pickup_completions := v_pickup_completions + 1;
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
    'pickup_completions', v_pickup_completions,
    'courier_reassignments', v_courier_reassignments,
    'late_flags', v_late_flags,
    'refunds', v_refunds
  );
END;
$$;
COMMIT;
