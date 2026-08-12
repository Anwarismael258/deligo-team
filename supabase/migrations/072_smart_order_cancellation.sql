CREATE TABLE IF NOT EXISTS public.refunds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID,
  user_id UUID,
  refund_amount NUMERIC DEFAULT 0,
  refund_percent NUMERIC DEFAULT 0,
  status TEXT DEFAULT 'completed',
  reason TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE IF EXISTS public.refunds
  ADD COLUMN IF NOT EXISTS order_id UUID,
  ADD COLUMN IF NOT EXISTS user_id UUID,
  ADD COLUMN IF NOT EXISTS refund_amount NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS refund_percent NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'completed',
  ADD COLUMN IF NOT EXISTS reason TEXT,
  ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'refunds' AND column_name = 'user_id'
  ) AND NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'refunds' AND policyname = 'refunds_select_own'
  ) THEN
    CREATE POLICY refunds_select_own
    ON public.refunds
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id OR public.is_admin());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'refunds' AND policyname = 'refunds_service_all'
  ) THEN
    CREATE POLICY refunds_service_all
      ON public.refunds
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
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
BEGIN
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
    WHEN 'pending' THEN v_refund_percent := 1.0;
    WHEN 'paid' THEN v_refund_percent := 1.0;
    WHEN 'accepted' THEN v_refund_percent := 0.8;
    WHEN 'preparing' THEN v_refund_percent := 0.0;
    ELSE v_refund_percent := 0.0;
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
GRANT EXECUTE ON FUNCTION public.process_order_cancellation(UUID, UUID, TEXT) TO authenticated, service_role;
