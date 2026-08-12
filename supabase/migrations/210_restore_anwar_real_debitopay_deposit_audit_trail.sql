BEGIN;
DO $$
DECLARE
  v_user_id UUID := '680a7827-68fe-49fa-b005-62e148a6e2b4';
  v_wallet_id UUID := '7bd7bbba-1caf-4cc8-bbad-99d30f472ba6';
BEGIN
  UPDATE public.wallets
  SET balance = 123.50,
      available_balance = 123.50,
      pending_balance = 0.00,
      updated_at = NOW()
  WHERE id = v_wallet_id
    AND user_id = v_user_id;

  INSERT INTO public.wallet_deposits (
    id,
    wallet_id,
    user_id,
    amount,
    payment_method,
    status,
    transaction_id,
    reference,
    gateway_fee,
    net_amount,
    provider_status,
    provider_payload,
    processed_at,
    created_at,
    updated_at
  )
  VALUES
    (
      '2694167d-8253-4902-a224-b821852cc755',
      v_wallet_id,
      v_user_id,
      10.00,
      'emola',
      'completed',
      'X7ZAAFCSKJSIKLHGTHADSDBT',
      'DEP_680a7827_1774198115055',
      0.50,
      9.50,
      'completed',
      jsonb_build_object(
        'provider', 'debito_pay',
        'status', 'completed',
        'transaction_id', 'X7ZAAFCSKJSIKLHGTHADSDBT'
      ),
      '2026-03-22T16:49:38.089899+00:00'::timestamptz,
      '2026-03-22T16:48:35.099578+00:00'::timestamptz,
      '2026-03-22T16:49:38.089899+00:00'::timestamptz
    ),
    (
      '5723c664-03b2-49d1-9b56-bba695c26494',
      v_wallet_id,
      v_user_id,
      110.00,
      'emola',
      'completed',
      'B7QOHIMHFVYNC6X43RRRFDBT',
      'DEP_680a7827_1774554660789',
      5.50,
      104.50,
      'completed',
      jsonb_build_object(
        'provider', 'debito_pay',
        'status', 'completed',
        'transaction_id', 'B7QOHIMHFVYNC6X43RRRFDBT'
      ),
      '2026-03-26T19:51:56.572653+00:00'::timestamptz,
      '2026-03-26T19:51:00.871307+00:00'::timestamptz,
      '2026-03-26T19:51:56.572653+00:00'::timestamptz
    ),
    (
      'ac5f632c-9476-46cc-bc51-35d905a5e7a5',
      v_wallet_id,
      v_user_id,
      10.00,
      'emola',
      'completed',
      '37Q67YBJMCVONGUIT3C7TDBT',
      'DEP_680a7827_1774712845359',
      0.50,
      9.50,
      'completed',
      jsonb_build_object(
        'provider', 'debito_pay',
        'status', 'completed',
        'transaction_id', '37Q67YBJMCVONGUIT3C7TDBT'
      ),
      '2026-03-28T15:58:10.200437+00:00'::timestamptz,
      '2026-03-28T15:47:25.414116+00:00'::timestamptz,
      '2026-03-28T15:58:10.200437+00:00'::timestamptz
    )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.wallet_ledger (
    id,
    wallet_id,
    user_id,
    direction,
    entry_type,
    amount,
    balance_before,
    balance_after,
    metadata,
    reference_key,
    status,
    created_at
  )
  VALUES
    (
      '2a40eabe-1b37-4972-9fb9-bd5edd41cc8a',
      v_wallet_id,
      v_user_id,
      'credit',
      'deposit_net',
      9.50,
      0.00,
      9.50,
      jsonb_build_object(
        'deposit_id', '2694167d-8253-4902-a224-b821852cc755',
        'gross_amount', 10.00,
        'gateway_fee', 0.50,
        'available_balance_before', 0.00,
        'available_balance_after', 9.50,
        'pending_balance_before', 0.00,
        'pending_balance_after', 0.00
      ),
      'deposit-net-2694167d-8253-4902-a224-b821852cc755',
      'confirmed',
      '2026-03-22T16:49:38.089899+00:00'::timestamptz
    ),
    (
      'd5f2b442-52d9-43c8-9c84-b77f567a4101',
      NULL,
      v_user_id,
      'debit',
      'deposit_gateway_fee',
      0.50,
      NULL,
      NULL,
      jsonb_build_object(
        'deposit_id', '2694167d-8253-4902-a224-b821852cc755',
        'gross_amount', 10.00
      ),
      'deposit-fee-2694167d-8253-4902-a224-b821852cc755',
      'confirmed',
      '2026-03-22T16:49:38.089899+00:00'::timestamptz
    ),
    (
      '431119d9-fcc6-41b0-966e-8846bae6bc23',
      v_wallet_id,
      v_user_id,
      'credit',
      'deposit_net',
      104.50,
      9.50,
      114.00,
      jsonb_build_object(
        'deposit_id', '5723c664-03b2-49d1-9b56-bba695c26494',
        'gross_amount', 110.00,
        'gateway_fee', 5.50,
        'available_balance_before', 9.50,
        'available_balance_after', 114.00,
        'pending_balance_before', 0.00,
        'pending_balance_after', 0.00
      ),
      'deposit-net-5723c664-03b2-49d1-9b56-bba695c26494',
      'confirmed',
      '2026-03-26T19:51:56.572653+00:00'::timestamptz
    ),
    (
      '8dfb96e5-6d67-4621-8be5-a7b2f57bbf82',
      NULL,
      v_user_id,
      'debit',
      'deposit_gateway_fee',
      5.50,
      NULL,
      NULL,
      jsonb_build_object(
        'deposit_id', '5723c664-03b2-49d1-9b56-bba695c26494',
        'gross_amount', 110.00
      ),
      'deposit-fee-5723c664-03b2-49d1-9b56-bba695c26494',
      'confirmed',
      '2026-03-26T19:51:56.572653+00:00'::timestamptz
    ),
    (
      '1696cdca-b416-4afd-a513-d3583cbfd0e6',
      v_wallet_id,
      v_user_id,
      'credit',
      'deposit_net',
      9.50,
      114.00,
      123.50,
      jsonb_build_object(
        'deposit_id', 'ac5f632c-9476-46cc-bc51-35d905a5e7a5',
        'gross_amount', 10.00,
        'gateway_fee', 0.50,
        'available_balance_before', 114.00,
        'available_balance_after', 123.50,
        'pending_balance_before', 0.00,
        'pending_balance_after', 0.00
      ),
      'deposit-net-ac5f632c-9476-46cc-bc51-35d905a5e7a5',
      'confirmed',
      '2026-03-28T15:58:10.200437+00:00'::timestamptz
    ),
    (
      'a989da49-eeb6-470e-a63b-b7369cc58417',
      NULL,
      v_user_id,
      'debit',
      'deposit_gateway_fee',
      0.50,
      NULL,
      NULL,
      jsonb_build_object(
        'deposit_id', 'ac5f632c-9476-46cc-bc51-35d905a5e7a5',
        'gross_amount', 10.00
      ),
      'deposit-fee-ac5f632c-9476-46cc-bc51-35d905a5e7a5',
      'confirmed',
      '2026-03-28T15:58:10.200437+00:00'::timestamptz
    )
  ON CONFLICT (id) DO NOTHING;
END $$;
COMMIT;
