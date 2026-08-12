BEGIN;
DO $$
DECLARE
  v_user_id UUID := '8891d8d0-afd0-44d0-b421-370b96213b1d';
  v_wallet_id UUID;
BEGIN
  SELECT id
  INTO v_wallet_id
  FROM public.wallets
  WHERE user_id = v_user_id
  ORDER BY is_default DESC, created_at ASC
  LIMIT 1;

  IF v_wallet_id IS NULL THEN
    RAISE EXCEPTION 'test_wallet_not_found_for_877688695';
  END IF;

  PERFORM public.apply_wallet_ledger_entry(
    p_wallet_id := v_wallet_id,
    p_user_id := v_user_id,
    p_direction := 'credit',
    p_entry_type := 'test_balance_credit',
    p_amount := 1000.00,
    p_reference_key := 'test-credit:877688695:2026-06-28:1000',
    p_metadata := jsonb_build_object(
      'source', 'admin_test_credit',
      'purpose', 'event_ticket_qr_end_to_end_test',
      'phone', '+258877688695',
      'is_fictitious', true
    ),
    p_status := 'confirmed',
    p_allow_negative := true
  );
END;
$$;
COMMIT;
