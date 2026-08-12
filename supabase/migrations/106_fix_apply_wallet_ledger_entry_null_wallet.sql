BEGIN;
CREATE OR REPLACE FUNCTION public.apply_wallet_ledger_entry(
  p_wallet_id UUID DEFAULT NULL,
  p_user_id UUID DEFAULT NULL,
  p_order_id UUID DEFAULT NULL,
  p_payment_id UUID DEFAULT NULL,
  p_direction TEXT DEFAULT 'credit',
  p_entry_type TEXT DEFAULT 'generic',
  p_amount NUMERIC DEFAULT 0,
  p_reference_key TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb,
  p_status TEXT DEFAULT 'confirmed',
  p_allow_negative BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing RECORD;
  v_wallet RECORD;
  v_effective_user_id UUID := p_user_id;
  v_before NUMERIC := NULL;
  v_after NUMERIC := NULL;
  v_delta NUMERIC;
  v_entry_id UUID;
  v_available_before NUMERIC := NULL;
  v_available_after NUMERIC := NULL;
  v_pending_before NUMERIC := NULL;
  v_pending_after NUMERIC := NULL;
BEGIN
  IF p_amount IS NULL OR p_amount < 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  IF p_direction NOT IN ('credit', 'debit') THEN
    RAISE EXCEPTION 'invalid_direction';
  END IF;

  IF p_status NOT IN ('pending', 'confirmed', 'failed', 'reversed') THEN
    RAISE EXCEPTION 'invalid_ledger_status';
  END IF;

  IF p_reference_key IS NOT NULL THEN
    SELECT id, wallet_id, balance_before, balance_after, status
    INTO v_existing
    FROM public.wallet_ledger
    WHERE reference_key = p_reference_key
    LIMIT 1;

    IF v_existing.id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'success', true,
        'duplicate', true,
        'ledger_id', v_existing.id,
        'status', v_existing.status,
        'balance_before', v_existing.balance_before,
        'balance_after', v_existing.balance_after
      );
    END IF;
  END IF;

  IF p_wallet_id IS NOT NULL THEN
    SELECT id, user_id, balance, available_balance, pending_balance
    INTO v_wallet
    FROM public.wallets
    WHERE id = p_wallet_id
    FOR UPDATE;

    IF v_wallet.id IS NULL THEN
      RAISE EXCEPTION 'wallet_not_found';
    END IF;

    v_effective_user_id := COALESCE(p_user_id, v_wallet.user_id);
    v_before := COALESCE(v_wallet.balance, 0);
    v_pending_before := COALESCE(v_wallet.pending_balance, 0);
    v_available_before := COALESCE(v_wallet.available_balance, 0);

    IF ABS((v_available_before + v_pending_before) - v_before) > 0.009 THEN
      v_available_before := GREATEST(v_before - v_pending_before, 0);
    END IF;

    v_delta := CASE WHEN p_direction = 'credit' THEN p_amount ELSE -p_amount END;

    IF p_status = 'confirmed' THEN
      v_available_after := ROUND((v_available_before + v_delta)::numeric, 2);
      v_pending_after := v_pending_before;
      IF p_direction = 'debit' AND NOT p_allow_negative AND v_available_after < 0 THEN
        RAISE EXCEPTION 'insufficient_available_balance';
      END IF;
      v_after := ROUND((v_available_after + v_pending_after)::numeric, 2);

      UPDATE public.wallets
      SET available_balance = v_available_after,
          pending_balance = v_pending_after,
          balance = v_after,
          updated_at = NOW()
      WHERE id = p_wallet_id;
    ELSIF p_status = 'pending' THEN
      v_available_after := v_available_before;
      v_pending_after := ROUND(
        (
          v_pending_before +
          CASE WHEN p_direction = 'credit' THEN p_amount ELSE 0 END
        )::numeric,
        2
      );
      v_after := ROUND((v_available_after + v_pending_after)::numeric, 2);

      UPDATE public.wallets
      SET available_balance = v_available_after,
          pending_balance = v_pending_after,
          balance = v_after,
          updated_at = NOW()
      WHERE id = p_wallet_id;
    ELSE
      v_available_after := v_available_before;
      v_pending_after := v_pending_before;
      v_after := v_before;
    END IF;
  END IF;

  INSERT INTO public.wallet_ledger (
    wallet_id,
    user_id,
    order_id,
    payment_id,
    direction,
    entry_type,
    amount,
    balance_before,
    balance_after,
    metadata,
    reference_key,
    status
  )
  VALUES (
    p_wallet_id,
    v_effective_user_id,
    p_order_id,
    p_payment_id,
    p_direction,
    p_entry_type,
    p_amount,
    v_before,
    v_after,
    COALESCE(
      p_metadata,
      '{}'::jsonb
    ) || jsonb_build_object(
      'available_balance_before', v_available_before,
      'available_balance_after', v_available_after,
      'pending_balance_before', v_pending_before,
      'pending_balance_after', v_pending_after
    ),
    p_reference_key,
    p_status
  )
  RETURNING id INTO v_entry_id;

  RETURN jsonb_build_object(
    'success', true,
    'duplicate', false,
    'ledger_id', v_entry_id,
    'balance_before', v_before,
    'balance_after', v_after,
    'available_balance_before', v_available_before,
    'available_balance_after', v_available_after,
    'pending_balance_before', v_pending_before,
    'pending_balance_after', v_pending_after,
    'status', p_status
  );
END;
$$;
COMMIT;
