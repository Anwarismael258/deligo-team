BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS public.order_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  actor_id UUID NULL,
  actor_role TEXT NULL,
  old_status TEXT NULL,
  new_status TEXT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_order_events_order_id_created_at
  ON public.order_events(order_id, created_at DESC);
ALTER TABLE public.order_events ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'order_events_select_related'
      AND polrelid = 'public.order_events'::regclass
  ) THEN
    CREATE POLICY order_events_select_related
      ON public.order_events
      FOR SELECT
      TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.orders o
          WHERE o.id = order_id
            AND (
              COALESCE(o.client_id, o.customer_id) = auth.uid()
              OR o.courier_id = auth.uid()
              OR EXISTS (
                SELECT 1
                FROM public.restaurants r
                WHERE r.id = o.restaurant_id
                  AND r.owner_id = auth.uid()
              )
            )
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'order_events_service_all'
      AND polrelid = 'public.order_events'::regclass
  ) THEN
    CREATE POLICY order_events_service_all
      ON public.order_events
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.order_disputes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  opened_by UUID NOT NULL,
  opened_by_role TEXT NOT NULL,
  dispute_type TEXT NOT NULL,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  resolution TEXT NULL,
  resolved_by UUID NULL,
  resolved_at TIMESTAMPTZ NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_order_disputes_order_id_created_at
  ON public.order_disputes(order_id, created_at DESC);
ALTER TABLE public.order_disputes ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'order_disputes_select_related'
      AND polrelid = 'public.order_disputes'::regclass
  ) THEN
    CREATE POLICY order_disputes_select_related
      ON public.order_disputes
      FOR SELECT
      TO authenticated
      USING (
        opened_by = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.orders o
          WHERE o.id = order_id
            AND (
              COALESCE(o.client_id, o.customer_id) = auth.uid()
              OR o.courier_id = auth.uid()
              OR EXISTS (
                SELECT 1
                FROM public.restaurants r
                WHERE r.id = o.restaurant_id
                  AND r.owner_id = auth.uid()
              )
            )
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'order_disputes_insert_related'
      AND polrelid = 'public.order_disputes'::regclass
  ) THEN
    CREATE POLICY order_disputes_insert_related
      ON public.order_disputes
      FOR INSERT
      TO authenticated
      WITH CHECK (opened_by = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polname = 'order_disputes_service_all'
      AND polrelid = 'public.order_disputes'::regclass
  ) THEN
    CREATE POLICY order_disputes_service_all
      ON public.order_disputes
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
ALTER TABLE IF EXISTS public.deliveries
  ADD COLUMN IF NOT EXISTS proof_photo_url TEXT,
  ADD COLUMN IF NOT EXISTS proof_notes TEXT,
  ADD COLUMN IF NOT EXISTS proof_taken_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS proof_latitude NUMERIC(10,8),
  ADD COLUMN IF NOT EXISTS proof_longitude NUMERIC(11,8),
  ADD COLUMN IF NOT EXISTS courier_started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS courier_arrived_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;
CREATE OR REPLACE FUNCTION public.log_order_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.order_events (
      order_id,
      event_type,
      old_status,
      new_status,
      metadata
    ) VALUES (
      NEW.id,
      'order_created',
      NULL,
      NEW.status,
      jsonb_build_object(
        'payment_status', NEW.payment_status,
        'restaurant_id', NEW.restaurant_id,
        'courier_id', NEW.courier_id,
        'delivery_fee', NEW.delivery_fee
      )
    );
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF COALESCE(OLD.status, '') IS DISTINCT FROM COALESCE(NEW.status, '') THEN
      INSERT INTO public.order_events (
        order_id,
        event_type,
        old_status,
        new_status,
        metadata
      ) VALUES (
        NEW.id,
        'status_changed',
        OLD.status,
        NEW.status,
        jsonb_build_object(
          'payment_status', NEW.payment_status,
          'courier_id', NEW.courier_id
        )
      );
    END IF;

    IF OLD.courier_id IS DISTINCT FROM NEW.courier_id THEN
      INSERT INTO public.order_events (
        order_id,
        event_type,
        old_status,
        new_status,
        metadata
      ) VALUES (
        NEW.id,
        CASE
          WHEN OLD.courier_id IS NULL AND NEW.courier_id IS NOT NULL THEN 'courier_assigned'
          WHEN OLD.courier_id IS NOT NULL AND NEW.courier_id IS NULL THEN 'courier_unassigned'
          ELSE 'courier_changed'
        END,
        OLD.status,
        NEW.status,
        jsonb_build_object(
          'old_courier_id', OLD.courier_id,
          'new_courier_id', NEW.courier_id
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_log_order_event_insert ON public.orders;
CREATE TRIGGER trg_log_order_event_insert
AFTER INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.log_order_event();
DROP TRIGGER IF EXISTS trg_log_order_event_update ON public.orders;
CREATE TRIGGER trg_log_order_event_update
AFTER UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.log_order_event();
CREATE OR REPLACE FUNCTION public.submit_delivery_proof(
  p_order_id UUID,
  p_courier_id UUID,
  p_photo_url TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_latitude NUMERIC DEFAULT NULL,
  p_longitude NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
BEGIN
  SELECT id, courier_id, status
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF v_order.courier_id IS DISTINCT FROM p_courier_id THEN
    RAISE EXCEPTION 'courier_not_assigned';
  END IF;

  UPDATE public.deliveries
  SET proof_photo_url = COALESCE(p_photo_url, proof_photo_url),
      proof_notes = COALESCE(p_notes, proof_notes),
      proof_taken_at = NOW(),
      proof_latitude = COALESCE(p_latitude, proof_latitude),
      proof_longitude = COALESCE(p_longitude, proof_longitude),
      updated_at = NOW()
  WHERE order_id = p_order_id;

  INSERT INTO public.order_events (
    order_id,
    event_type,
    actor_id,
    actor_role,
    old_status,
    new_status,
    metadata
  ) VALUES (
    p_order_id,
    'delivery_proof_submitted',
    p_courier_id,
    'courier',
    v_order.status,
    v_order.status,
    jsonb_build_object(
      'photo_url', p_photo_url,
      'notes', p_notes,
      'proof_latitude', p_latitude,
      'proof_longitude', p_longitude
    )
  );

  RETURN jsonb_build_object('success', true, 'order_id', p_order_id);
END;
$$;
CREATE OR REPLACE FUNCTION public.open_order_dispute(
  p_order_id UUID,
  p_opened_by UUID,
  p_opened_by_role TEXT,
  p_dispute_type TEXT,
  p_reason TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.order_disputes (
    order_id,
    opened_by,
    opened_by_role,
    dispute_type,
    reason,
    metadata
  ) VALUES (
    p_order_id,
    p_opened_by,
    p_opened_by_role,
    p_dispute_type,
    p_reason,
    COALESCE(p_metadata, '{}'::jsonb)
  )
  RETURNING id INTO v_id;

  INSERT INTO public.order_events (
    order_id,
    event_type,
    actor_id,
    actor_role,
    metadata
  ) VALUES (
    p_order_id,
    'dispute_opened',
    p_opened_by,
    p_opened_by_role,
    jsonb_build_object(
      'dispute_id', v_id,
      'dispute_type', p_dispute_type,
      'reason', p_reason
    )
  );

  RETURN jsonb_build_object('success', true, 'dispute_id', v_id);
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
  v_order RECORD;
BEGIN
  FOR v_order IN
    SELECT *
    FROM public.orders
    WHERE status IN ('pending', 'paid')
      AND created_at < NOW() - INTERVAL '15 minutes'
      AND COALESCE(payment_status, 'pending') IN ('pending', 'completed')
  LOOP
    IF v_order.payment_status = 'completed' THEN
      PERFORM public.apply_wallet_ledger_entry(
        p_wallet_id := (SELECT id FROM public.wallets WHERE user_id = COALESCE(v_order.client_id, v_order.customer_id) LIMIT 1),
        p_user_id := COALESCE(v_order.client_id, v_order.customer_id),
        p_order_id := v_order.id,
        p_direction := 'credit',
        p_entry_type := 'order_timeout_refund',
        p_amount := COALESCE(v_order.total_amount, 0),
        p_reference_key := 'order-timeout-refund-' || v_order.id::text,
        p_metadata := jsonb_build_object('reason', 'restaurant_timeout'),
        p_status := 'confirmed'
      );
      v_refunds := v_refunds + 1;
    END IF;

    UPDATE public.orders
    SET status = 'cancelled',
        payment_status = CASE WHEN payment_status = 'completed' THEN 'refunded' ELSE payment_status END,
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
      jsonb_build_object('auto', true)
    );

    v_restaurant_timeouts := v_restaurant_timeouts + 1;
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
      jsonb_build_object('source', 'stuck_order_sweep', 'reason', 'no_movement_after_assignment')
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
      jsonb_build_object('source', 'stuck_order_sweep', 'reason', 'transit_sla_exceeded')
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
    'courier_reassignments', v_courier_reassignments,
    'late_flags', v_late_flags,
    'refunds', v_refunds
  );
END;
$$;
CREATE OR REPLACE VIEW public.admin_order_operations_overview AS
SELECT
  o.id AS order_id,
  o.status,
  o.payment_status,
  COALESCE(o.client_id, o.customer_id) AS client_id,
  o.restaurant_id,
  o.courier_id,
  o.total_amount,
  o.delivery_fee,
  o.delivery_address,
  o.delivery_latitude,
  o.delivery_longitude,
  o.created_at,
  o.updated_at,
  CASE
    WHEN o.status IN ('pending', 'paid') AND o.created_at < NOW() - INTERVAL '15 minutes' THEN 'restaurant_timeout'
    WHEN o.status = 'courier_assigned' AND o.updated_at < NOW() - INTERVAL '20 minutes' THEN 'courier_not_moving'
    WHEN o.status IN ('in_transit', 'arrived') AND o.updated_at < NOW() - INTERVAL '60 minutes' THEN 'delivery_sla_exceeded'
    ELSE NULL
  END AS operational_alert,
  d.status AS delivery_status,
  d.current_latitude,
  d.current_longitude,
  d.proof_photo_url,
  d.proof_taken_at,
  dis.status AS dispute_status,
  dis.dispute_type,
  dis.created_at AS dispute_created_at
FROM public.orders o
LEFT JOIN public.deliveries d ON d.order_id = o.id
LEFT JOIN LATERAL (
  SELECT dispute_type, status, created_at
  FROM public.order_disputes od
  WHERE od.order_id = o.id
  ORDER BY created_at DESC
  LIMIT 1
) dis ON true;
COMMIT;
