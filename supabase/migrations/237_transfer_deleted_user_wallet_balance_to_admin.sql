BEGIN;
CREATE OR REPLACE FUNCTION public.transfer_deleted_user_wallet_balance_to_admin(
  p_user_id UUID,
  p_request_id UUID DEFAULT NULL,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID;
  v_source_wallet public.wallets%ROWTYPE;
  v_admin_wallet public.wallets%ROWTYPE;
  v_reference_base TEXT;
  v_existing RECORD;
  v_reason TEXT := NULLIF(BTRIM(COALESCE(p_reason, '')), '');
  v_total_balance NUMERIC := 0;
  v_available_before NUMERIC := 0;
  v_pending_before NUMERIC := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id_required';
  END IF;

  v_admin_id := COALESCE(
    public.resolve_platform_user_id(),
    (
      SELECT id
      FROM public.profiles
      WHERE role = 'admin'
      ORDER BY created_at ASC
      LIMIT 1
    )
  );

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'admin_wallet_user_not_found';
  END IF;

  IF v_admin_id = p_user_id THEN
    RETURN jsonb_build_object(
      'success', true,
      'transferred', false,
      'reason', 'source_is_admin',
      'amount', 0,
      'admin_user_id', v_admin_id
    );
  END IF;

  v_reference_base := 'account-deletion-transfer:' ||
    COALESCE(p_request_id::text, p_user_id::text);

  PERFORM pg_advisory_xact_lock(hashtextextended(v_reference_base, 0));

  SELECT *
  INTO v_source_wallet
  FROM public.wallets
  WHERE user_id = p_user_id
  ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF v_source_wallet.id IS NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'transferred', false,
      'reason', 'wallet_not_found',
      'amount', 0,
      'admin_user_id', v_admin_id
    );
  END IF;

  SELECT id, amount
  INTO v_existing
  FROM public.wallet_ledger
  WHERE reference_key = v_reference_base || ':source'
  LIMIT 1;

  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'transferred', true,
      'duplicate', true,
      'amount', ROUND(COALESCE(v_existing.amount, 0), 2),
      'currency', COALESCE(v_source_wallet.currency, 'MZN'),
      'wallet_id', v_source_wallet.id,
      'admin_user_id', v_admin_id
    );
  END IF;

  v_total_balance := ROUND(
    GREATEST(
      COALESCE(v_source_wallet.balance, 0),
      COALESCE(v_source_wallet.available_balance, 0) +
        COALESCE(v_source_wallet.pending_balance, 0),
      0
    ),
    2
  );

  IF v_total_balance <= 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'transferred', false,
      'reason', 'no_balance',
      'amount', 0,
      'currency', COALESCE(v_source_wallet.currency, 'MZN'),
      'wallet_id', v_source_wallet.id,
      'admin_user_id', v_admin_id
    );
  END IF;

  v_available_before := ROUND(
    COALESCE(
      v_source_wallet.available_balance,
      GREATEST(
        v_total_balance - COALESCE(v_source_wallet.pending_balance, 0),
        0
      )
    ),
    2
  );
  v_pending_before := ROUND(
    COALESCE(
      v_source_wallet.pending_balance,
      GREATEST(v_total_balance - v_available_before, 0)
    ),
    2
  );

  IF ABS((v_available_before + v_pending_before) - v_total_balance) > 0.009 THEN
    v_available_before := v_total_balance;
    v_pending_before := 0;
  END IF;

  v_admin_wallet := public.ensure_user_wallet(
    v_admin_id,
    COALESCE(NULLIF(v_source_wallet.currency, ''), 'MZN')
  );

  UPDATE public.wallets
  SET balance = 0,
      available_balance = 0,
      pending_balance = 0,
      updated_at = NOW()
  WHERE id = v_source_wallet.id;

  INSERT INTO public.wallet_ledger (
    wallet_id,
    user_id,
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
    v_source_wallet.id,
    p_user_id,
    'debit',
    'account_deletion_admin_transfer_out',
    v_total_balance,
    v_total_balance,
    0,
    jsonb_build_object(
      'origin', 'account_deletion_transfer',
      'request_id', p_request_id,
      'reason', v_reason,
      'admin_user_id', v_admin_id,
      'admin_wallet_id', v_admin_wallet.id,
      'available_balance_before', v_available_before,
      'available_balance_after', 0,
      'pending_balance_before', v_pending_before,
      'pending_balance_after', 0
    ),
    v_reference_base || ':source',
    'confirmed'
  );

  PERFORM public.apply_wallet_ledger_entry(
    p_wallet_id := v_admin_wallet.id,
    p_user_id := v_admin_id,
    p_direction := 'credit',
    p_entry_type := 'account_deletion_admin_transfer_in',
    p_amount := v_total_balance,
    p_reference_key := v_reference_base || ':admin',
    p_metadata := jsonb_build_object(
      'origin', 'account_deletion_transfer',
      'request_id', p_request_id,
      'reason', v_reason,
      'source_user_id', p_user_id,
      'source_wallet_id', v_source_wallet.id
    ),
    p_status := 'confirmed'
  );

  IF to_regclass('public.admin_actions_log') IS NOT NULL THEN
    INSERT INTO public.admin_actions_log (
      admin_id,
      user_id,
      action,
      reason,
      metadata
    )
    VALUES (
      v_admin_id,
      p_user_id,
      'account_deletion_wallet_transfer',
      v_reason,
      jsonb_build_object(
        'amount', v_total_balance,
        'currency', COALESCE(v_source_wallet.currency, 'MZN'),
        'request_id', p_request_id,
        'source_wallet_id', v_source_wallet.id,
        'admin_wallet_id', v_admin_wallet.id,
        'source', 'account_deletion'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'transferred', true,
    'amount', v_total_balance,
    'currency', COALESCE(v_source_wallet.currency, 'MZN'),
    'wallet_id', v_source_wallet.id,
    'admin_wallet_id', v_admin_wallet.id,
    'admin_user_id', v_admin_id
  );
END;
$$;
REVOKE ALL ON FUNCTION public.transfer_deleted_user_wallet_balance_to_admin(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transfer_deleted_user_wallet_balance_to_admin(UUID, UUID, TEXT) TO service_role;
COMMIT;
