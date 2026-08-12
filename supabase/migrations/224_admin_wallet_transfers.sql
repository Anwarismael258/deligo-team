BEGIN;
CREATE OR REPLACE FUNCTION public.admin_transfer_wallet_balance(
  p_target_user_id UUID,
  p_amount NUMERIC,
  p_reason TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_admin_wallet public.wallets%ROWTYPE;
  v_target_wallet public.wallets%ROWTYPE;
  v_target_profile public.profiles%ROWTYPE;
  v_reference_base TEXT := 'admin-transfer:' || gen_random_uuid()::text;
  v_reason TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_only';
  END IF;

  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_target_user_id IS NULL THEN
    RAISE EXCEPTION 'target_user_required';
  END IF;

  IF p_target_user_id = v_admin_id THEN
    RAISE EXCEPTION 'target_must_be_different_from_admin';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  SELECT *
  INTO v_target_profile
  FROM public.profiles
  WHERE id = p_target_user_id
    AND role IN ('client', 'customer', 'courier', 'restaurant')
  LIMIT 1;

  IF v_target_profile.id IS NULL THEN
    RAISE EXCEPTION 'target_user_not_found';
  END IF;

  v_admin_wallet := public.ensure_user_wallet(v_admin_id, 'MZN');
  v_target_wallet := public.ensure_user_wallet(p_target_user_id, 'MZN');

  PERFORM public.apply_wallet_ledger_entry(
    p_wallet_id := v_admin_wallet.id,
    p_user_id := v_admin_id,
    p_direction := 'debit',
    p_entry_type := 'admin_transfer_out',
    p_amount := ROUND(p_amount::numeric, 2),
    p_reference_key := v_reference_base || ':debit',
    p_metadata := jsonb_build_object(
      'origin', 'admin_wallet_transfer',
      'target_user_id', p_target_user_id,
      'target_role', v_target_profile.role,
      'reason', v_reason,
      'source', 'admin_panel'
    ),
    p_status := 'confirmed',
    p_allow_negative := FALSE
  );

  PERFORM public.apply_wallet_ledger_entry(
    p_wallet_id := v_target_wallet.id,
    p_user_id := p_target_user_id,
    p_direction := 'credit',
    p_entry_type := 'admin_transfer_in',
    p_amount := ROUND(p_amount::numeric, 2),
    p_reference_key := v_reference_base || ':credit',
    p_metadata := jsonb_build_object(
      'origin', 'admin_wallet_transfer',
      'admin_id', v_admin_id,
      'reason', v_reason,
      'source', 'admin_panel'
    ),
    p_status := 'confirmed'
  );

  INSERT INTO public.admin_actions_log (
    admin_id,
    user_id,
    action,
    reason,
    metadata
  )
  VALUES (
    v_admin_id,
    p_target_user_id,
    'wallet_transfer',
    v_reason,
    jsonb_build_object(
      'amount', ROUND(p_amount::numeric, 2),
      'currency', 'MZN',
      'target_wallet_id', v_target_wallet.id,
      'source_wallet_id', v_admin_wallet.id,
      'source', 'admin_panel'
    ) || COALESCE(p_metadata, '{}'::jsonb)
  );

  PERFORM public.create_app_notification(
    p_user_id := p_target_user_id,
    p_type := 'WALLET_TRANSFER_RECEIVED',
    p_title := 'Transferencia recebida',
    p_body := 'Recebeu saldo na sua carteira Deligo.',
    p_action := 'wallet',
    p_entity_id := v_target_wallet.id::text,
    p_priority := 'HIGH',
    p_channel := 'system',
    p_metadata := jsonb_build_object(
      'amount', ROUND(p_amount::numeric, 2),
      'currency', 'MZN',
      'admin_id', v_admin_id,
      'reason', v_reason,
      'source', 'admin_wallet_transfer'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Transferencia concluida com sucesso.',
    'target_wallet_id', v_target_wallet.id,
    'target_user_id', p_target_user_id,
    'amount', ROUND(p_amount::numeric, 2),
    'currency', 'MZN'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_transfer_wallet_balance(UUID, NUMERIC, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_transfer_wallet_balance(UUID, NUMERIC, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_transfer_wallet_balance(UUID, NUMERIC, TEXT, JSONB) TO service_role;
COMMIT;
