-- Fallback RPC for account deletion requests (when edge function is unavailable)
CREATE OR REPLACE FUNCTION public.request_account_deletion_rpc(
  p_confirm_text TEXT,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_profile RECORD;
  v_wallet RECORD;
  v_active_orders_count INTEGER := 0;
  v_available_balance NUMERIC := 0;
  v_pending_balance NUMERIC := 0;
  v_requires_manual_review BOOLEAN := FALSE;
  v_request_id UUID;
  v_settings JSONB := '{}'::jsonb;
  v_now TIMESTAMPTZ := NOW();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  IF UPPER(TRIM(COALESCE(p_confirm_text, ''))) <> 'DELETE' THEN
    RAISE EXCEPTION 'confirmation_text_mismatch';
  END IF;

  SELECT p.id, p.role, p.full_name, p.email, p.phone, p.settings
  INTO v_profile
  FROM public.profiles p
  WHERE p.id = v_user_id;

  SELECT w.balance, w.available_balance, w.pending_balance, w.currency
  INTO v_wallet
  FROM public.wallets w
  WHERE w.user_id = v_user_id
  ORDER BY w.updated_at DESC
  LIMIT 1;

  SELECT COUNT(*)::INTEGER
  INTO v_active_orders_count
  FROM public.orders o
  WHERE (o.client_id = v_user_id OR o.customer_id = v_user_id OR o.courier_id = v_user_id)
    AND o.status IN ('pending', 'accepted', 'preparing', 'ready', 'picked_up', 'in_transit');

  v_available_balance := COALESCE(v_wallet.available_balance, v_wallet.balance, 0);
  v_pending_balance := COALESCE(v_wallet.pending_balance, 0);
  v_requires_manual_review := (v_active_orders_count > 0 OR v_available_balance > 0 OR v_pending_balance > 0);

  SELECT adr.id
  INTO v_request_id
  FROM public.account_deletion_requests adr
  WHERE adr.user_id = v_user_id
    AND adr.status IN ('pending', 'approved')
  ORDER BY adr.requested_at DESC
  LIMIT 1;

  IF v_request_id IS NULL THEN
    INSERT INTO public.account_deletion_requests (
      user_id,
      email,
      role,
      status,
      reason,
      source,
      metadata
    )
    VALUES (
      v_user_id,
      COALESCE(v_profile.email, NULL),
      COALESCE(v_profile.role, NULL),
      'pending',
      NULLIF(TRIM(COALESCE(p_reason, '')), ''),
      'mobile_app',
      jsonb_build_object(
        'active_orders_count', v_active_orders_count,
        'wallet_available_balance', v_available_balance,
        'wallet_pending_balance', v_pending_balance,
        'wallet_currency', COALESCE(v_wallet.currency, 'MZN'),
        'requires_manual_review', v_requires_manual_review
      )
    )
    RETURNING id INTO v_request_id;
  END IF;

  v_settings := COALESCE(v_profile.settings, '{}'::jsonb);
  v_settings := jsonb_set(v_settings, '{account_deletion_requested}', 'true'::jsonb, true);
  v_settings := jsonb_set(v_settings, '{account_deletion_requested_at}', to_jsonb(v_now), true);
  v_settings := jsonb_set(v_settings, '{account_deletion_request_source}', to_jsonb('mobile_app'::text), true);
  IF COALESCE(TRIM(p_reason), '') <> '' THEN
    v_settings := jsonb_set(v_settings, '{account_deletion_reason}', to_jsonb(TRIM(p_reason)), true);
  END IF;

  UPDATE public.profiles
  SET settings = v_settings,
      updated_at = v_now
  WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', v_request_id,
    'status', 'pending',
    'requires_manual_review', v_requires_manual_review,
    'active_orders_count', v_active_orders_count,
    'wallet_available_balance', v_available_balance,
    'wallet_pending_balance', v_pending_balance,
    'message', CASE
      WHEN v_requires_manual_review THEN 'Pedido recebido. A conta sera analisada antes da exclusao definitiva.'
      ELSE 'Pedido recebido. A exclusao da conta sera processada em breve.'
    END
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.request_account_deletion_rpc(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_account_deletion_rpc(TEXT, TEXT) TO authenticated;
