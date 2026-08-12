ALTER TABLE IF EXISTS public.profiles
  ADD COLUMN IF NOT EXISTS fraud_score INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_suspicious BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS block_reason TEXT,
  ADD COLUMN IF NOT EXISTS last_fraud_event_at TIMESTAMPTZ;
CREATE TABLE IF NOT EXISTS public.user_fraud_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  event_type TEXT NOT NULL,
  severity TEXT DEFAULT 'medium',
  points INTEGER DEFAULT 0,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.user_fraud_events ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'user_fraud_events' AND policyname = 'user_fraud_events_service_all'
  ) THEN
    CREATE POLICY user_fraud_events_service_all
      ON public.user_fraud_events
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_user_fraud_events_user_id_created_at
  ON public.user_fraud_events(user_id, created_at DESC);
CREATE OR REPLACE FUNCTION public.register_user_fraud_event(
  p_user_id UUID,
  p_event_type TEXT,
  p_points INTEGER DEFAULT 0,
  p_severity TEXT DEFAULT 'medium',
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_new_score INTEGER := 0;
BEGIN
  INSERT INTO public.user_fraud_events (
    user_id, event_type, severity, points, metadata
  )
  VALUES (
    p_user_id, p_event_type, p_severity, p_points, COALESCE(p_metadata, '{}'::jsonb)
  );

  UPDATE public.profiles
  SET fraud_score = COALESCE(fraud_score, 0) + COALESCE(p_points, 0),
      is_suspicious = CASE
        WHEN COALESCE(fraud_score, 0) + COALESCE(p_points, 0) >= 40 THEN TRUE
        ELSE COALESCE(is_suspicious, FALSE)
      END,
      is_blocked = CASE
        WHEN COALESCE(fraud_score, 0) + COALESCE(p_points, 0) >= 80 THEN TRUE
        ELSE COALESCE(is_blocked, FALSE)
      END,
      block_reason = CASE
        WHEN COALESCE(fraud_score, 0) + COALESCE(p_points, 0) >= 80
          THEN COALESCE(block_reason, 'Conta bloqueada por comportamento suspeito.')
        ELSE block_reason
      END,
      last_fraud_event_at = now()
  WHERE id = p_user_id
  RETURNING fraud_score INTO v_new_score;
END;
$$;
CREATE OR REPLACE FUNCTION public.enforce_order_access_for_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_profile RECORD;
  v_cancel_count INTEGER := 0;
BEGIN
  SELECT id, is_blocked, is_suspicious, block_reason
  INTO v_profile
  FROM public.profiles
  WHERE id = COALESCE(NEW.client_id, NEW.customer_id)
  LIMIT 1;

  IF v_profile.is_blocked THEN
    RAISE EXCEPTION 'account_blocked:%', COALESCE(v_profile.block_reason, 'Conta bloqueada');
  END IF;

  SELECT COUNT(*)
  INTO v_cancel_count
  FROM public.orders
  WHERE (client_id = COALESCE(NEW.client_id, NEW.customer_id) OR customer_id = COALESCE(NEW.client_id, NEW.customer_id))
    AND status = 'cancelled'
    AND created_at >= now() - interval '24 hours';

  IF v_cancel_count >= 3 THEN
    PERFORM public.register_user_fraud_event(
      COALESCE(NEW.client_id, NEW.customer_id),
      'too_many_daily_cancellations',
      20,
      'high',
      jsonb_build_object('cancel_count_24h', v_cancel_count)
    );
    RAISE EXCEPTION 'daily_cancellation_limit_reached';
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_order_access_for_user ON public.orders;
CREATE TRIGGER trg_enforce_order_access_for_user
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.enforce_order_access_for_user();
CREATE OR REPLACE VIEW public.admin_fraud_overview AS
SELECT
  p.id AS user_id,
  p.full_name,
  p.phone,
  p.role,
  p.fraud_score,
  p.is_suspicious,
  p.is_blocked,
  p.block_reason,
  p.last_fraud_event_at,
  COALESCE(o.cancelled_24h, 0) AS cancelled_orders_last_24h,
  COALESCE(o.completed_30d, 0) AS completed_orders_last_30d,
  COALESCE(r.refunds_30d, 0) AS refunds_last_30d,
  COALESCE(dupe.duplicate_accounts, 0) AS duplicate_accounts_by_phone
FROM public.profiles p
LEFT JOIN (
  SELECT
    COALESCE(client_id, customer_id) AS user_id,
    COUNT(*) FILTER (WHERE status = 'cancelled' AND created_at >= now() - interval '24 hours') AS cancelled_24h,
    COUNT(*) FILTER (WHERE status IN ('delivered', 'completed') AND created_at >= now() - interval '30 days') AS completed_30d
  FROM public.orders
  GROUP BY COALESCE(client_id, customer_id)
) o ON o.user_id = p.id
LEFT JOIN (
  SELECT user_id, COUNT(*) AS refunds_30d
  FROM public.refunds
  WHERE created_at >= now() - interval '30 days'
  GROUP BY user_id
) r ON r.user_id = p.id
LEFT JOIN (
  SELECT
    phone,
    COUNT(*) AS duplicate_accounts
  FROM public.profiles
  WHERE phone IS NOT NULL AND btrim(phone) <> ''
  GROUP BY phone
  HAVING COUNT(*) > 1
) dupe ON dupe.phone = p.phone;
CREATE OR REPLACE FUNCTION public.process_order_cancellation(
  p_order_id UUID,
  p_user_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order RECORD;
  v_payment_split RECORD;
  v_client_wallet RECORD;
  v_restaurant_wallet RECORD;
  v_restaurant_owner UUID;
  v_refund_percent NUMERIC := 0;
  v_refund_amount NUMERIC := 0;
  v_recovery_from_restaurant NUMERIC := 0;
  v_client_before NUMERIC := 0;
  v_client_after NUMERIC := 0;
  v_restaurant_before NUMERIC := 0;
  v_restaurant_after NUMERIC := 0;
  v_message TEXT := '';
  v_cancel_count INTEGER := 0;
  v_points INTEGER := 0;
BEGIN
  SELECT COUNT(*)
  INTO v_cancel_count
  FROM public.orders
  WHERE (client_id = p_user_id OR customer_id = p_user_id)
    AND status = 'cancelled'
    AND created_at >= now() - interval '24 hours';

  IF v_cancel_count >= 3 THEN
    PERFORM public.register_user_fraud_event(
      p_user_id,
      'daily_cancellation_limit_reached',
      25,
      'high',
      jsonb_build_object('cancel_count_24h', v_cancel_count)
    );
    RAISE EXCEPTION 'daily_cancellation_limit_reached';
  END IF;

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND (client_id = p_user_id OR customer_id = p_user_id)
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF v_order.status IN ('in_transit', 'courier_assigned', 'on_the_way', 'arrived', 'delivered', 'completed') THEN
    PERFORM public.register_user_fraud_event(
      p_user_id,
      'late_cancellation_attempt',
      12,
      'medium',
      jsonb_build_object('order_id', p_order_id, 'status', v_order.status)
    );
    RAISE EXCEPTION 'cancellation_not_allowed';
  END IF;

  IF v_order.status = 'cancelled' THEN
    RETURN jsonb_build_object(
      'success', true,
      'status', 'cancelled',
      'refund_percent', 0,
      'refund_amount', 0,
      'message', 'Pedido já estava cancelado.'
    );
  END IF;

  CASE v_order.status
    WHEN 'pending' THEN
      v_refund_percent := 1.0;
      v_points := 1;
    WHEN 'paid' THEN
      v_refund_percent := 1.0;
      v_points := 2;
    WHEN 'accepted' THEN
      v_refund_percent := 0.8;
      v_points := 8;
    WHEN 'preparing' THEN
      v_refund_percent := 0.0;
      v_points := 12;
    ELSE
      v_refund_percent := 0.0;
      v_points := 5;
  END CASE;

  v_refund_amount := ROUND(COALESCE(v_order.total_amount, 0) * v_refund_percent, 2);

  SELECT *
  INTO v_payment_split
  FROM public.payment_splits
  WHERE order_id = p_order_id
  FOR UPDATE;

  IF v_refund_amount > 0 THEN
    SELECT *
    INTO v_client_wallet
    FROM public.wallets
    WHERE user_id = p_user_id
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'client_wallet_not_found';
    END IF;

    IF v_order.status = 'accepted' AND v_payment_split.status = 'restaurant_confirmed' THEN
      SELECT COALESCE(owner_id, user_id)
      INTO v_restaurant_owner
      FROM public.restaurants
      WHERE id = v_order.restaurant_id
      LIMIT 1;

      IF v_restaurant_owner IS NOT NULL THEN
        SELECT *
        INTO v_restaurant_wallet
        FROM public.wallets
        WHERE user_id = v_restaurant_owner
        LIMIT 1
        FOR UPDATE;

        IF FOUND THEN
          v_recovery_from_restaurant := LEAST(
            ROUND(COALESCE(v_payment_split.restaurant_amount, 0), 2),
            ROUND(COALESCE(v_restaurant_wallet.balance, 0), 2),
            v_refund_amount
          );

          IF v_recovery_from_restaurant > 0 THEN
            v_restaurant_before := COALESCE(v_restaurant_wallet.balance, 0);
            v_restaurant_after := ROUND(v_restaurant_before - v_recovery_from_restaurant, 2);

            UPDATE public.wallets
            SET balance = v_restaurant_after,
                updated_at = now()
            WHERE id = v_restaurant_wallet.id;

            INSERT INTO public.wallet_ledger (
              wallet_id, user_id, order_id, direction, entry_type, amount,
              balance_before, balance_after, metadata
            )
            VALUES (
              v_restaurant_wallet.id,
              v_restaurant_owner,
              p_order_id,
              'debit',
              'restaurant_cancellation_reversal',
              v_recovery_from_restaurant,
              v_restaurant_before,
              v_restaurant_after,
              jsonb_build_object(
                'reason', COALESCE(p_reason, 'customer_cancellation'),
                'refund_percent', v_refund_percent
              )
            );
          END IF;
        END IF;
      END IF;
    END IF;

    v_client_before := COALESCE(v_client_wallet.balance, 0);
    v_client_after := ROUND(v_client_before + v_refund_amount, 2);

    UPDATE public.wallets
    SET balance = v_client_after,
        updated_at = now()
    WHERE id = v_client_wallet.id;

    INSERT INTO public.wallet_ledger (
      wallet_id, user_id, order_id, direction, entry_type, amount,
      balance_before, balance_after, metadata
    )
    VALUES (
      v_client_wallet.id,
      p_user_id,
      p_order_id,
      'credit',
      'order_cancellation_refund',
      v_refund_amount,
      v_client_before,
      v_client_after,
      jsonb_build_object(
        'reason', COALESCE(p_reason, 'customer_cancellation'),
        'refund_percent', v_refund_percent,
        'recovered_from_restaurant', v_recovery_from_restaurant
      )
    );
  END IF;

  UPDATE public.orders
  SET status = 'cancelled',
      updated_at = now()
  WHERE id = p_order_id;

  IF FOUND AND v_payment_split.order_id IS NOT NULL THEN
    UPDATE public.payment_splits
    SET status = 'cancelled',
        escrow_amount = GREATEST(COALESCE(escrow_amount, 0) - v_refund_amount, 0),
        settled_at = now()
    WHERE order_id = p_order_id;
  END IF;

  INSERT INTO public.refunds (
    order_id, user_id, refund_amount, refund_percent, status, reason, metadata
  )
  VALUES (
    p_order_id,
    p_user_id,
    v_refund_amount,
    ROUND(v_refund_percent * 100, 2),
    CASE WHEN v_refund_amount > 0 THEN 'completed' ELSE 'no_refund' END,
    COALESCE(p_reason, 'customer_cancellation'),
    jsonb_build_object(
      'order_status', v_order.status,
      'recovered_from_restaurant', v_recovery_from_restaurant
    )
  );

  PERFORM public.register_user_fraud_event(
    p_user_id,
    'order_cancelled_by_customer',
    v_points,
    CASE WHEN v_points >= 10 THEN 'high' WHEN v_points >= 5 THEN 'medium' ELSE 'low' END,
    jsonb_build_object(
      'order_id', p_order_id,
      'status', v_order.status,
      'refund_percent', ROUND(v_refund_percent * 100, 2),
      'refund_amount', v_refund_amount,
      'cancel_count_24h', v_cancel_count + 1
    )
  );

  IF v_order.status = 'pending' OR v_order.status = 'paid' THEN
    v_message := 'Pedido cancelado com reembolso total.';
  ELSIF v_order.status = 'accepted' THEN
    v_message := 'Pedido cancelado com reembolso parcial de 80%.';
  ELSIF v_order.status = 'preparing' THEN
    v_message := 'Pedido cancelado sem reembolso porque já estava em preparação.';
  ELSE
    v_message := 'Pedido cancelado.';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', 'cancelled',
    'refund_percent', ROUND(v_refund_percent * 100, 2),
    'refund_amount', v_refund_amount,
    'message', v_message
  );
END;
$$;
