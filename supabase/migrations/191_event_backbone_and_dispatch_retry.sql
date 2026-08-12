BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
ALTER TABLE public.order_events
  ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT,
  ADD COLUMN IF NOT EXISTS correlation_id TEXT;
UPDATE public.order_events
SET payload = COALESCE(NULLIF(payload, '{}'::jsonb), metadata, '{}'::jsonb)
WHERE payload IS NULL
   OR payload = '{}'::jsonb;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'order_events_idempotency_key_key'
      AND conrelid = 'public.order_events'::regclass
  ) THEN
    ALTER TABLE public.order_events
      ADD CONSTRAINT order_events_idempotency_key_key UNIQUE (idempotency_key);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_order_events_event_type_created_at
  ON public.order_events(event_type, created_at DESC);
CREATE OR REPLACE FUNCTION public.order_event_topic(
  p_event_type TEXT,
  p_old_status TEXT DEFAULT NULL,
  p_new_status TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_event_type TEXT := LOWER(COALESCE(btrim(p_event_type), ''));
  v_old_status TEXT := LOWER(COALESCE(btrim(p_old_status), ''));
  v_new_status TEXT := LOWER(COALESCE(btrim(p_new_status), ''));
BEGIN
  IF v_event_type = '' THEN
    RETURN 'ORDER_EVENT_UNKNOWN';
  END IF;

  IF v_event_type = 'status_changed' THEN
    CASE v_new_status
      WHEN 'accepted' THEN RETURN 'ORDER_ACCEPTED';
      WHEN 'preparing' THEN RETURN 'ORDER_PREPARING';
      WHEN 'ready' THEN RETURN 'ORDER_READY';
      WHEN 'courier_assigned' THEN RETURN 'COURIER_ASSIGNED';
      WHEN 'in_transit' THEN RETURN 'ORDER_PICKED_UP';
      WHEN 'arrived' THEN RETURN 'ORDER_ARRIVED';
      WHEN 'delivered' THEN RETURN 'ORDER_DELIVERED';
      WHEN 'completed' THEN RETURN 'ORDER_COMPLETED';
      WHEN 'auto_completed' THEN RETURN 'ORDER_AUTO_COMPLETED';
      WHEN 'cancelled' THEN RETURN 'ORDER_CANCELLED';
      WHEN 'expired' THEN RETURN 'ORDER_EXPIRED';
      WHEN 'disputed' THEN RETURN 'ORDER_DISPUTED';
      ELSE
        RETURN 'ORDER_STATUS_' || UPPER(REPLACE(COALESCE(v_new_status, 'unknown'), ' ', '_'));
    END CASE;
  END IF;

  CASE v_event_type
    WHEN 'order_created' THEN RETURN 'ORDER_CREATED';
    WHEN 'courier_assigned' THEN RETURN 'COURIER_ASSIGNED';
    WHEN 'courier_changed' THEN RETURN 'COURIER_CHANGED';
    WHEN 'courier_unassigned' THEN RETURN 'COURIER_UNASSIGNED';
    WHEN 'pickup_confirmed_by_customer' THEN RETURN 'ORDER_COMPLETED';
    WHEN 'pickup_auto_completed' THEN RETURN 'ORDER_AUTO_COMPLETED';
    WHEN 'delivery_auto_completed' THEN RETURN 'ORDER_AUTO_COMPLETED';
    WHEN 'delivery_problem_reported' THEN RETURN 'ORDER_DISPUTED';
    WHEN 'delivery_extension_requested' THEN RETURN 'DELIVERY_EXTENSION_REQUESTED';
    WHEN 'delivery_otp_issued' THEN RETURN 'DELIVERY_OTP_ISSUED';
    WHEN 'delivery_otp_regenerated' THEN RETURN 'DELIVERY_OTP_REGENERATED';
    WHEN 'delivery_otp_verified_event' THEN RETURN 'ORDER_DELIVERED';
    WHEN 'settlement_processed' THEN RETURN 'PAYMENT_RELEASED';
    WHEN 'refund_issued' THEN RETURN 'REFUND_INITIATED';
    WHEN 'restaurant_timeout_cancel_failed' THEN RETURN 'ORDER_TIMEOUT_CANCEL_FAILED';
    WHEN 'pickup_auto_complete_failed' THEN RETURN 'ORDER_AUTO_COMPLETE_FAILED';
    WHEN 'delivery_auto_complete_failed' THEN RETURN 'ORDER_AUTO_COMPLETE_FAILED';
    WHEN 'courier_reassignment_requested' THEN RETURN 'COURIER_REASSIGNMENT_REQUESTED';
    WHEN 'delivery_sla_exceeded' THEN RETURN 'DELIVERY_SLA_EXCEEDED';
    ELSE
      RETURN UPPER(REGEXP_REPLACE(v_event_type, '[^a-z0-9]+', '_', 'g'));
  END CASE;
END;
$$;
CREATE OR REPLACE FUNCTION public.prepare_order_event_row()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.payload IS NULL OR NEW.payload = '{}'::jsonb THEN
    NEW.payload := COALESCE(NEW.metadata, '{}'::jsonb);
  END IF;

  IF NEW.metadata IS NULL OR NEW.metadata = '{}'::jsonb THEN
    NEW.metadata := COALESCE(NEW.payload, '{}'::jsonb);
  END IF;

  IF NEW.correlation_id IS NULL
     AND COALESCE(NEW.payload, '{}'::jsonb) ? 'correlation_id' THEN
    NEW.correlation_id := NULLIF(NEW.payload ->> 'correlation_id', '');
  END IF;

  IF NEW.idempotency_key IS NULL
     AND COALESCE(NEW.payload, '{}'::jsonb) ? 'idempotency_key' THEN
    NEW.idempotency_key := NULLIF(NEW.payload ->> 'idempotency_key', '');
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_prepare_order_event_row ON public.order_events;
CREATE TRIGGER trg_prepare_order_event_row
BEFORE INSERT ON public.order_events
FOR EACH ROW
EXECUTE FUNCTION public.prepare_order_event_row();
CREATE OR REPLACE FUNCTION public.build_order_event_idempotency_key(
  p_order_id UUID,
  p_event_type TEXT,
  p_actor_id UUID DEFAULT NULL,
  p_old_status TEXT DEFAULT NULL,
  p_new_status TEXT DEFAULT NULL,
  p_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT md5(
    concat_ws(
      '|',
      'order_event',
      COALESCE(p_order_id::text, ''),
      LOWER(COALESCE(btrim(p_event_type), '')),
      COALESCE(p_actor_id::text, ''),
      LOWER(COALESCE(btrim(p_old_status), '')),
      LOWER(COALESCE(btrim(p_new_status), '')),
      md5(COALESCE(p_payload::text, '{}'::text))
    )
  );
$$;
CREATE OR REPLACE FUNCTION public.append_order_event(
  p_order_id UUID,
  p_event_type TEXT,
  p_actor_id UUID DEFAULT NULL,
  p_actor_role TEXT DEFAULT NULL,
  p_old_status TEXT DEFAULT NULL,
  p_new_status TEXT DEFAULT NULL,
  p_payload JSONB DEFAULT '{}'::jsonb,
  p_idempotency_key TEXT DEFAULT NULL,
  p_correlation_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id UUID;
  v_payload JSONB := COALESCE(p_payload, '{}'::jsonb);
  v_idempotency_key TEXT := COALESCE(
    NULLIF(btrim(p_idempotency_key), ''),
    public.build_order_event_idempotency_key(
      p_order_id := p_order_id,
      p_event_type := p_event_type,
      p_actor_id := p_actor_id,
      p_old_status := p_old_status,
      p_new_status := p_new_status,
      p_payload := v_payload
    )
  );
BEGIN
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'order_id_required';
  END IF;

  IF COALESCE(btrim(p_event_type), '') = '' THEN
    RAISE EXCEPTION 'event_type_required';
  END IF;

  INSERT INTO public.order_events (
    order_id,
    event_type,
    actor_id,
    actor_role,
    old_status,
    new_status,
    metadata,
    payload,
    idempotency_key,
    correlation_id
  )
  VALUES (
    p_order_id,
    p_event_type,
    p_actor_id,
    p_actor_role,
    p_old_status,
    p_new_status,
    v_payload,
    v_payload,
    v_idempotency_key,
    NULLIF(btrim(p_correlation_id), '')
  )
  ON CONFLICT (idempotency_key) DO UPDATE
  SET payload = public.order_events.payload
  RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.log_order_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.append_order_event(
      p_order_id := NEW.id,
      p_event_type := 'order_created',
      p_old_status := NULL,
      p_new_status := NEW.status,
      p_payload := jsonb_build_object(
        'payment_status', NEW.payment_status,
        'restaurant_id', NEW.restaurant_id,
        'courier_id', NEW.courier_id,
        'delivery_fee', NEW.delivery_fee,
        'source', 'orders_trigger'
      ),
      p_idempotency_key := 'orders-trigger:insert:' || NEW.id::text
    );
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF COALESCE(OLD.status, '') IS DISTINCT FROM COALESCE(NEW.status, '') THEN
      PERFORM public.append_order_event(
        p_order_id := NEW.id,
        p_event_type := 'status_changed',
        p_old_status := OLD.status,
        p_new_status := NEW.status,
        p_payload := jsonb_build_object(
          'payment_status', NEW.payment_status,
          'courier_id', NEW.courier_id,
          'source', 'orders_trigger'
        ),
        p_idempotency_key := public.build_order_event_idempotency_key(
          p_order_id := NEW.id,
          p_event_type := 'status_changed',
          p_actor_id := NULL,
          p_old_status := OLD.status,
          p_new_status := NEW.status,
          p_payload := jsonb_build_object(
            'payment_status', NEW.payment_status,
            'courier_id', NEW.courier_id,
            'source', 'orders_trigger'
          )
        )
      );
    END IF;

    IF OLD.courier_id IS DISTINCT FROM NEW.courier_id THEN
      PERFORM public.append_order_event(
        p_order_id := NEW.id,
        p_event_type := CASE
          WHEN OLD.courier_id IS NULL AND NEW.courier_id IS NOT NULL THEN 'courier_assigned'
          WHEN OLD.courier_id IS NOT NULL AND NEW.courier_id IS NULL THEN 'courier_unassigned'
          ELSE 'courier_changed'
        END,
        p_old_status := OLD.status,
        p_new_status := NEW.status,
        p_payload := jsonb_build_object(
          'old_courier_id', OLD.courier_id,
          'new_courier_id', NEW.courier_id,
          'source', 'orders_trigger'
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
ALTER TABLE public.push_notifications
  ADD COLUMN IF NOT EXISTS source_event_id UUID REFERENCES public.order_events(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS dispatch_key TEXT;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'push_notifications_dispatch_key_key'
      AND conrelid = 'public.push_notifications'::regclass
  ) THEN
    ALTER TABLE public.push_notifications
      ADD CONSTRAINT push_notifications_dispatch_key_key UNIQUE (dispatch_key);
  END IF;
END $$;
DROP FUNCTION IF EXISTS public.create_app_notification(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB);
CREATE OR REPLACE FUNCTION public.create_app_notification(
  p_user_id UUID,
  p_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_action TEXT DEFAULT NULL,
  p_entity_id TEXT DEFAULT NULL,
  p_priority TEXT DEFAULT 'NORMAL',
  p_channel TEXT DEFAULT 'system',
  p_metadata JSONB DEFAULT '{}'::jsonb,
  p_source_event_id UUID DEFAULT NULL,
  p_dispatch_key TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_dispatch_key IS NOT NULL THEN
    SELECT id
    INTO v_id
    FROM public.push_notifications
    WHERE dispatch_key = p_dispatch_key
    LIMIT 1;

    IF v_id IS NOT NULL THEN
      RETURN v_id;
    END IF;
  END IF;

  INSERT INTO public.push_notifications (
    user_id,
    type,
    title,
    body,
    action,
    entity_id,
    priority,
    channel,
    data,
    metadata,
    source_event_id,
    dispatch_key,
    created_at
  )
  VALUES (
    p_user_id,
    p_type,
    p_title,
    p_body,
    p_action,
    p_entity_id,
    p_priority,
    p_channel,
    p_metadata,
    p_metadata,
    p_source_event_id,
    p_dispatch_key,
    NOW()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
CREATE TABLE IF NOT EXISTS public.order_event_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_topic TEXT NOT NULL,
  channel TEXT NOT NULL,
  target_role TEXT NOT NULL,
  handler TEXT NOT NULL DEFAULT 'send_notification',
  template_key TEXT,
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT order_event_subscriptions_channel_check
    CHECK (channel IN ('push', 'sms', 'email', 'webhook', 'internal')),
  CONSTRAINT order_event_subscriptions_target_role_check
    CHECK (target_role IN ('customer', 'courier', 'restaurant_owner', 'admin'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_order_event_subscriptions_unique
  ON public.order_event_subscriptions(event_topic, channel, target_role, handler);
DROP TRIGGER IF EXISTS trg_order_event_subscriptions_touch_updated_at ON public.order_event_subscriptions;
CREATE TRIGGER trg_order_event_subscriptions_touch_updated_at
BEFORE UPDATE ON public.order_event_subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();
ALTER TABLE public.order_event_subscriptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS order_event_subscriptions_service_all ON public.order_event_subscriptions;
CREATE POLICY order_event_subscriptions_service_all
  ON public.order_event_subscriptions
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
CREATE TABLE IF NOT EXISTS public.order_event_dispatch_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.order_events(id) ON DELETE CASCADE,
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  event_topic TEXT NOT NULL,
  channel TEXT NOT NULL,
  target_role TEXT NOT NULL,
  target_user_id UUID,
  handler TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  notification_key TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  retry_count INTEGER NOT NULL DEFAULT 0,
  max_retries INTEGER NOT NULL DEFAULT 5,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_attempt_at TIMESTAMPTZ,
  locked_at TIMESTAMPTZ,
  locked_by TEXT,
  last_error TEXT,
  notification_id UUID REFERENCES public.push_notifications(id) ON DELETE SET NULL,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT order_event_dispatch_jobs_status_check
    CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'skipped', 'dead_letter')),
  CONSTRAINT order_event_dispatch_jobs_channel_check
    CHECK (channel IN ('push', 'sms', 'email', 'webhook', 'internal')),
  CONSTRAINT order_event_dispatch_jobs_target_role_check
    CHECK (target_role IN ('customer', 'courier', 'restaurant_owner', 'admin'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_order_event_dispatch_jobs_notification_key
  ON public.order_event_dispatch_jobs(notification_key);
CREATE INDEX IF NOT EXISTS idx_order_event_dispatch_jobs_status_attempt
  ON public.order_event_dispatch_jobs(status, next_attempt_at, created_at);
CREATE INDEX IF NOT EXISTS idx_order_event_dispatch_jobs_event_id
  ON public.order_event_dispatch_jobs(event_id);
CREATE INDEX IF NOT EXISTS idx_order_event_dispatch_jobs_target_user
  ON public.order_event_dispatch_jobs(target_user_id, created_at DESC);
DROP TRIGGER IF EXISTS trg_order_event_dispatch_jobs_touch_updated_at ON public.order_event_dispatch_jobs;
CREATE TRIGGER trg_order_event_dispatch_jobs_touch_updated_at
BEFORE UPDATE ON public.order_event_dispatch_jobs
FOR EACH ROW
EXECUTE FUNCTION public.touch_updated_at();
ALTER TABLE public.order_event_dispatch_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS order_event_dispatch_jobs_service_all ON public.order_event_dispatch_jobs;
CREATE POLICY order_event_dispatch_jobs_service_all
  ON public.order_event_dispatch_jobs
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
CREATE TABLE IF NOT EXISTS public.order_event_dispatch_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES public.order_event_dispatch_jobs(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES public.order_events(id) ON DELETE CASCADE,
  notification_key TEXT NOT NULL,
  attempt_number INTEGER NOT NULL,
  worker_id TEXT,
  status TEXT NOT NULL,
  request_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  response_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  error_text TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT order_event_dispatch_attempts_status_check
    CHECK (status IN ('processing', 'sent', 'failed', 'skipped'))
);
CREATE INDEX IF NOT EXISTS idx_order_event_dispatch_attempts_job_created_at
  ON public.order_event_dispatch_attempts(job_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_event_dispatch_attempts_event_id
  ON public.order_event_dispatch_attempts(event_id, created_at DESC);
ALTER TABLE public.order_event_dispatch_attempts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS order_event_dispatch_attempts_service_all ON public.order_event_dispatch_attempts;
CREATE POLICY order_event_dispatch_attempts_service_all
  ON public.order_event_dispatch_attempts
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
CREATE OR REPLACE FUNCTION public.build_order_event_notification_key(
  p_event_topic TEXT,
  p_order_id UUID,
  p_channel TEXT,
  p_target_user_id UUID DEFAULT NULL,
  p_purpose TEXT DEFAULT 'primary'
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT md5(
    concat_ws(
      '|',
      'notification',
      UPPER(COALESCE(btrim(p_event_topic), '')),
      COALESCE(p_order_id::text, ''),
      LOWER(COALESCE(btrim(p_channel), '')),
      COALESCE(p_target_user_id::text, ''),
      LOWER(COALESCE(btrim(p_purpose), 'primary'))
    )
  );
$$;
CREATE OR REPLACE FUNCTION public.resolve_order_event_target_users(
  p_order_id UUID,
  p_target_role TEXT
)
RETURNS TABLE(target_user_id UUID)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_role TEXT := LOWER(COALESCE(btrim(p_target_role), ''));
BEGIN
  IF p_order_id IS NULL OR v_target_role = '' THEN
    RETURN;
  END IF;

  IF v_target_role = 'customer' THEN
    RETURN QUERY
    SELECT COALESCE(o.client_id, o.customer_id)
    FROM public.orders o
    WHERE o.id = p_order_id
      AND COALESCE(o.client_id, o.customer_id) IS NOT NULL;
    RETURN;
  END IF;

  IF v_target_role = 'courier' THEN
    RETURN QUERY
    SELECT o.courier_id
    FROM public.orders o
    WHERE o.id = p_order_id
      AND o.courier_id IS NOT NULL;
    RETURN;
  END IF;

  IF v_target_role = 'restaurant_owner' THEN
    RETURN QUERY
    SELECT r.owner_id
    FROM public.orders o
    JOIN public.restaurants r
      ON r.id = o.restaurant_id
    WHERE o.id = p_order_id
      AND r.owner_id IS NOT NULL;
    RETURN;
  END IF;

  IF v_target_role = 'admin' THEN
    RETURN QUERY
    SELECT p.id
    FROM public.profiles p
    WHERE LOWER(COALESCE(p.role, '')) = 'admin';
    RETURN;
  END IF;
END;
$$;
CREATE OR REPLACE FUNCTION public.enqueue_order_event_dispatches(
  p_event_id UUID,
  p_reason TEXT DEFAULT 'primary',
  p_include_disabled BOOLEAN DEFAULT FALSE
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event public.order_events%rowtype;
  v_event_topic TEXT;
  v_subscription RECORD;
  v_target RECORD;
  v_count INTEGER := 0;
  v_notification_key TEXT;
BEGIN
  SELECT *
  INTO v_event
  FROM public.order_events
  WHERE id = p_event_id;

  IF v_event.id IS NULL THEN
    RAISE EXCEPTION 'order_event_not_found';
  END IF;

  v_event_topic := public.order_event_topic(
    p_event_type := v_event.event_type,
    p_old_status := v_event.old_status,
    p_new_status := v_event.new_status
  );

  FOR v_subscription IN
    SELECT *
    FROM public.order_event_subscriptions
    WHERE event_topic = v_event_topic
      AND (enabled = TRUE OR p_include_disabled = TRUE)
  LOOP
    FOR v_target IN
      SELECT target_user_id
      FROM public.resolve_order_event_target_users(v_event.order_id, v_subscription.target_role)
    LOOP
      v_notification_key := public.build_order_event_notification_key(
        p_event_topic := v_event_topic,
        p_order_id := v_event.order_id,
        p_channel := v_subscription.channel,
        p_target_user_id := v_target.target_user_id,
        p_purpose := COALESCE(NULLIF(btrim(p_reason), ''), 'primary')
      );

      INSERT INTO public.order_event_dispatch_jobs (
        event_id,
        order_id,
        event_topic,
        channel,
        target_role,
        target_user_id,
        handler,
        status,
        notification_key,
        payload
      )
      VALUES (
        v_event.id,
        v_event.order_id,
        v_event_topic,
        v_subscription.channel,
        v_subscription.target_role,
        v_target.target_user_id,
        v_subscription.handler,
        'pending',
        v_notification_key,
        COALESCE(v_event.payload, '{}'::jsonb)
          || jsonb_build_object(
            'event_id', v_event.id,
            'order_id', v_event.order_id,
            'event_type', v_event.event_type,
            'event_topic', v_event_topic,
            'old_status', v_event.old_status,
            'new_status', v_event.new_status,
            'dispatch_reason', COALESCE(NULLIF(btrim(p_reason), ''), 'primary'),
            'subscription_id', v_subscription.id,
            'target_role', v_subscription.target_role,
            'channel', v_subscription.channel,
            'handler', v_subscription.handler,
            'target_user_id', v_target.target_user_id
          )
          || COALESCE(v_subscription.metadata, '{}'::jsonb)
      )
      ON CONFLICT (notification_key) DO NOTHING;

      IF FOUND THEN
        v_count := v_count + 1;
      END IF;
    END LOOP;
  END LOOP;

  RETURN v_count;
END;
$$;
CREATE OR REPLACE FUNCTION public.trg_enqueue_order_event_dispatches()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.enqueue_order_event_dispatches(
    p_event_id := NEW.id,
    p_reason := 'primary',
    p_include_disabled := FALSE
  );
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enqueue_order_event_dispatches ON public.order_events;
CREATE TRIGGER trg_enqueue_order_event_dispatches
AFTER INSERT ON public.order_events
FOR EACH ROW
EXECUTE FUNCTION public.trg_enqueue_order_event_dispatches();
CREATE OR REPLACE FUNCTION public.replay_order_event(
  p_event_id UUID,
  p_reason TEXT DEFAULT 'manual_replay',
  p_requested_by UUID DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reason TEXT := COALESCE(NULLIF(btrim(p_reason), ''), 'manual_replay');
BEGIN
  RETURN public.enqueue_order_event_dispatches(
    p_event_id := p_event_id,
    p_reason := 'replay:' || v_reason || ':' || COALESCE(p_requested_by::text, 'system'),
    p_include_disabled := TRUE
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.claim_order_event_dispatch_jobs(
  p_worker_id TEXT,
  p_limit INTEGER DEFAULT 25
)
RETURNS SETOF public.order_event_dispatch_jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 200);
BEGIN
  RETURN QUERY
  WITH picked AS (
    SELECT j.id
    FROM public.order_event_dispatch_jobs j
    WHERE j.status IN ('pending', 'failed')
      AND COALESCE(j.next_attempt_at, NOW()) <= NOW()
      AND (
        j.locked_at IS NULL
        OR j.locked_at <= NOW() - INTERVAL '10 minutes'
      )
    ORDER BY j.next_attempt_at NULLS FIRST, j.created_at
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  ),
  updated AS (
    UPDATE public.order_event_dispatch_jobs j
    SET status = 'processing',
        locked_at = NOW(),
        locked_by = COALESCE(NULLIF(btrim(p_worker_id), ''), 'event_worker'),
        last_attempt_at = NOW(),
        updated_at = NOW()
    FROM picked
    WHERE j.id = picked.id
    RETURNING j.*
  ),
  attempts AS (
    INSERT INTO public.order_event_dispatch_attempts (
      job_id,
      event_id,
      notification_key,
      attempt_number,
      worker_id,
      status,
      request_payload
    )
    SELECT
      u.id,
      u.event_id,
      u.notification_key,
      u.retry_count + 1,
      COALESCE(NULLIF(btrim(p_worker_id), ''), 'event_worker'),
      'processing',
      u.payload
    FROM updated u
    RETURNING job_id
  )
  SELECT u.*
  FROM updated u;
END;
$$;
CREATE OR REPLACE FUNCTION public.mark_order_event_dispatch_sent(
  p_job_id UUID,
  p_worker_id TEXT DEFAULT NULL,
  p_notification_id UUID DEFAULT NULL,
  p_response_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS public.order_event_dispatch_jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.order_event_dispatch_jobs%rowtype;
BEGIN
  UPDATE public.order_event_dispatch_jobs
  SET status = 'sent',
      notification_id = COALESCE(p_notification_id, notification_id),
      sent_at = COALESCE(sent_at, NOW()),
      locked_at = NULL,
      locked_by = NULL,
      last_error = NULL,
      updated_at = NOW()
  WHERE id = p_job_id
  RETURNING * INTO v_job;

  IF v_job.id IS NULL THEN
    RAISE EXCEPTION 'dispatch_job_not_found';
  END IF;

  UPDATE public.order_event_dispatch_attempts
  SET status = 'sent',
      response_payload = COALESCE(p_response_payload, '{}'::jsonb),
      error_text = NULL
  WHERE id = (
    SELECT a.id
    FROM public.order_event_dispatch_attempts a
    WHERE a.job_id = p_job_id
      AND a.status = 'processing'
      AND (
        p_worker_id IS NULL
        OR COALESCE(a.worker_id, '') = COALESCE(p_worker_id, '')
      )
    ORDER BY a.created_at DESC
    LIMIT 1
  );

  RETURN v_job;
END;
$$;
CREATE OR REPLACE FUNCTION public.mark_order_event_dispatch_failed(
  p_job_id UUID,
  p_worker_id TEXT DEFAULT NULL,
  p_error_text TEXT DEFAULT NULL,
  p_response_payload JSONB DEFAULT '{}'::jsonb,
  p_retry_delay_seconds INTEGER DEFAULT NULL,
  p_skip BOOLEAN DEFAULT FALSE
)
RETURNS public.order_event_dispatch_jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.order_event_dispatch_jobs%rowtype;
  v_retry_delay_seconds INTEGER;
  v_next_status TEXT;
BEGIN
  SELECT *
  INTO v_job
  FROM public.order_event_dispatch_jobs
  WHERE id = p_job_id
  FOR UPDATE;

  IF v_job.id IS NULL THEN
    RAISE EXCEPTION 'dispatch_job_not_found';
  END IF;

  v_retry_delay_seconds := COALESCE(
    p_retry_delay_seconds,
    LEAST(3600, GREATEST(60, (2 ^ GREATEST(v_job.retry_count, 0)) * 60))
  );

  v_next_status := CASE
    WHEN p_skip THEN 'skipped'
    WHEN v_job.retry_count + 1 >= v_job.max_retries THEN 'dead_letter'
    ELSE 'failed'
  END;

  UPDATE public.order_event_dispatch_jobs
  SET status = v_next_status,
      retry_count = CASE
        WHEN p_skip THEN retry_count
        ELSE retry_count + 1
      END,
      next_attempt_at = CASE
        WHEN v_next_status = 'failed' THEN NOW() + make_interval(secs => v_retry_delay_seconds)
        ELSE next_attempt_at
      END,
      locked_at = NULL,
      locked_by = NULL,
      last_error = COALESCE(p_error_text, last_error, 'dispatch_failed'),
      updated_at = NOW()
  WHERE id = p_job_id
  RETURNING * INTO v_job;

  UPDATE public.order_event_dispatch_attempts
  SET status = CASE WHEN p_skip THEN 'skipped' ELSE 'failed' END,
      response_payload = COALESCE(p_response_payload, '{}'::jsonb),
      error_text = COALESCE(p_error_text, error_text, 'dispatch_failed')
  WHERE id = (
    SELECT a.id
    FROM public.order_event_dispatch_attempts a
    WHERE a.job_id = p_job_id
      AND a.status = 'processing'
      AND (
        p_worker_id IS NULL
        OR COALESCE(a.worker_id, '') = COALESCE(p_worker_id, '')
      )
    ORDER BY a.created_at DESC
    LIMIT 1
  );

  RETURN v_job;
END;
$$;
CREATE OR REPLACE FUNCTION public.reset_stale_order_event_dispatch_jobs(
  p_stale_after_minutes INTEGER DEFAULT 10
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  UPDATE public.order_event_dispatch_jobs
  SET status = CASE
        WHEN retry_count + 1 >= max_retries THEN 'dead_letter'
        ELSE 'failed'
      END,
      retry_count = CASE
        WHEN retry_count + 1 >= max_retries THEN retry_count
        ELSE retry_count + 1
      END,
      next_attempt_at = NOW() + INTERVAL '5 minutes',
      locked_at = NULL,
      locked_by = NULL,
      last_error = COALESCE(last_error, 'stale_processing_lock_reset'),
      updated_at = NOW()
  WHERE status = 'processing'
    AND locked_at <= NOW() - make_interval(mins => LEAST(GREATEST(COALESCE(p_stale_after_minutes, 10), 1), 120));

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
INSERT INTO public.order_event_subscriptions (
  event_topic,
  channel,
  target_role,
  handler,
  template_key,
  enabled,
  metadata
)
VALUES
  ('ORDER_ACCEPTED', 'push', 'customer', 'send_notification', 'order_accepted_customer', FALSE, jsonb_build_object('phase', 'event_backbone')),
  ('ORDER_READY', 'push', 'customer', 'send_notification', 'order_ready_customer', FALSE, jsonb_build_object('phase', 'event_backbone')),
  ('ORDER_DELIVERED', 'push', 'customer', 'send_notification', 'order_delivered_customer', FALSE, jsonb_build_object('phase', 'event_backbone')),
  ('ORDER_AUTO_COMPLETED', 'push', 'customer', 'send_notification', 'order_auto_completed_customer', FALSE, jsonb_build_object('phase', 'event_backbone')),
  ('ORDER_DISPUTED', 'push', 'admin', 'send_notification', 'order_disputed_admin', FALSE, jsonb_build_object('phase', 'event_backbone')),
  ('DELIVERY_EXTENSION_REQUESTED', 'push', 'courier', 'send_notification', 'delivery_extension_courier', FALSE, jsonb_build_object('phase', 'event_backbone')),
  ('DELIVERY_SLA_EXCEEDED', 'push', 'restaurant_owner', 'send_notification', 'delivery_sla_restaurant', FALSE, jsonb_build_object('phase', 'event_backbone'))
ON CONFLICT DO NOTHING;
DROP VIEW IF EXISTS public.order_event_dispatch_health;
CREATE VIEW public.order_event_dispatch_health AS
SELECT
  COUNT(*) AS total_jobs,
  COUNT(*) FILTER (WHERE status = 'pending') AS pending_jobs,
  COUNT(*) FILTER (WHERE status = 'processing') AS processing_jobs,
  COUNT(*) FILTER (WHERE status = 'failed') AS failed_jobs,
  COUNT(*) FILTER (WHERE status = 'dead_letter') AS dead_letter_jobs,
  COUNT(*) FILTER (WHERE status = 'sent') AS sent_jobs,
  COUNT(*) FILTER (WHERE status = 'skipped') AS skipped_jobs,
  MIN(next_attempt_at) FILTER (WHERE status IN ('pending', 'failed')) AS next_due_at,
  MAX(updated_at) AS last_job_update_at
FROM public.order_event_dispatch_jobs;
DROP VIEW IF EXISTS public.order_event_stream;
CREATE VIEW public.order_event_stream AS
SELECT
  oe.id,
  oe.order_id,
  public.order_event_topic(oe.event_type, oe.old_status, oe.new_status) AS event_topic,
  oe.event_type,
  oe.actor_id,
  oe.actor_role,
  oe.old_status,
  oe.new_status,
  COALESCE(NULLIF(oe.payload, '{}'::jsonb), oe.metadata, '{}'::jsonb) AS payload,
  oe.metadata,
  oe.idempotency_key,
  oe.correlation_id,
  oe.created_at
FROM public.order_events oe;
DROP VIEW IF EXISTS public.order_operational_audit_log;
CREATE VIEW public.order_operational_audit_log AS
SELECT *
FROM public.order_event_stream oes
WHERE oes.event_topic NOT LIKE 'PAYMENT_%'
  AND oes.event_topic NOT LIKE 'REFUND_%';
DROP VIEW IF EXISTS public.order_financial_audit_log;
CREATE VIEW public.order_financial_audit_log AS
SELECT
  oes.*,
  o.payment_status,
  o.funds_status,
  o.currency
FROM public.order_event_stream oes
JOIN public.orders o
  ON o.id = oes.order_id
WHERE oes.event_topic LIKE 'PAYMENT_%'
   OR oes.event_topic LIKE 'REFUND_%'
   OR oes.event_type IN ('settlement_processed', 'refund_issued');
DROP VIEW IF EXISTS public.order_event_dispatch_timeline;
CREATE VIEW public.order_event_dispatch_timeline AS
SELECT
  j.id AS job_id,
  j.event_id,
  j.order_id,
  j.event_topic,
  j.channel,
  j.target_role,
  j.target_user_id,
  j.handler,
  j.status,
  j.notification_key,
  j.retry_count,
  j.max_retries,
  j.next_attempt_at,
  j.last_attempt_at,
  j.locked_at,
  j.locked_by,
  j.last_error,
  j.notification_id,
  j.sent_at,
  j.created_at,
  a.id AS attempt_id,
  a.attempt_number,
  a.worker_id,
  a.status AS attempt_status,
  a.error_text,
  a.created_at AS attempt_created_at
FROM public.order_event_dispatch_jobs j
LEFT JOIN public.order_event_dispatch_attempts a
  ON a.job_id = j.id;
REVOKE ALL ON FUNCTION public.append_order_event(UUID, TEXT, UUID, TEXT, TEXT, TEXT, JSONB, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.append_order_event(UUID, TEXT, UUID, TEXT, TEXT, TEXT, JSONB, TEXT, TEXT) TO service_role;
REVOKE ALL ON FUNCTION public.enqueue_order_event_dispatches(UUID, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_order_event_dispatches(UUID, TEXT, BOOLEAN) TO service_role;
REVOKE ALL ON FUNCTION public.replay_order_event(UUID, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.replay_order_event(UUID, TEXT, UUID) TO service_role;
REVOKE ALL ON FUNCTION public.claim_order_event_dispatch_jobs(TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_order_event_dispatch_jobs(TEXT, INTEGER) TO service_role;
REVOKE ALL ON FUNCTION public.mark_order_event_dispatch_sent(UUID, TEXT, UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_order_event_dispatch_sent(UUID, TEXT, UUID, JSONB) TO service_role;
REVOKE ALL ON FUNCTION public.mark_order_event_dispatch_failed(UUID, TEXT, TEXT, JSONB, INTEGER, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_order_event_dispatch_failed(UUID, TEXT, TEXT, JSONB, INTEGER, BOOLEAN) TO service_role;
REVOKE ALL ON FUNCTION public.reset_stale_order_event_dispatch_jobs(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reset_stale_order_event_dispatch_jobs(INTEGER) TO service_role;
COMMIT;
