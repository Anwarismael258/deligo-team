BEGIN;
CREATE OR REPLACE FUNCTION public.reconcile_stale_wallet_v2_requests()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_withdrawal RECORD;
  v_wallet_id UUID;
  v_failed_deposits INTEGER := 0;
  v_reversed_withdrawals INTEGER := 0;
BEGIN
  UPDATE public.wallet_deposits
  SET status = 'failed',
      provider_status = 'no_provider_reference',
      provider_payload = jsonb_build_object(
        'source', 'wallet_v2_stale_reconciliation',
        'reason', 'provider_request_not_created'
      ),
      processed_at = now(),
      updated_at = now()
  WHERE status IN ('pending', 'processing')
    AND NULLIF(trim(transaction_id), '') IS NULL
    AND created_at < now() - interval '10 minutes';

  GET DIAGNOSTICS v_failed_deposits = ROW_COUNT;

  FOR v_withdrawal IN
    SELECT id, user_id, amount, method, phone_number
    FROM public.withdrawal_requests
    WHERE status IN ('pending', 'processing')
      AND NULLIF(trim(transaction_id), '') IS NULL
      AND NULLIF(trim(provider_reference), '') IS NULL
      AND created_at < now() - interval '10 minutes'
    FOR UPDATE
  LOOP
    SELECT id INTO v_wallet_id
    FROM public.wallets
    WHERE user_id = v_withdrawal.user_id
    ORDER BY is_default DESC, created_at ASC
    LIMIT 1;

    IF v_wallet_id IS NOT NULL AND EXISTS (
      SELECT 1
      FROM public.wallet_ledger
      WHERE reference_key = 'withdrawal-' || v_withdrawal.id::text
        AND direction = 'debit'
        AND status = 'confirmed'
    ) THEN
      PERFORM public.apply_wallet_ledger_entry(
        p_wallet_id := v_wallet_id,
        p_user_id := v_withdrawal.user_id,
        p_direction := 'credit',
        p_entry_type := 'withdrawal_reversed',
        p_amount := v_withdrawal.amount,
        p_reference_key := 'withdrawal-reversal-' || v_withdrawal.id::text,
        p_metadata := jsonb_build_object(
          'withdrawal_request_id', v_withdrawal.id,
          'method', v_withdrawal.method,
          'phone_number', v_withdrawal.phone_number,
          'reason', 'provider_request_not_created',
          'source', 'wallet_v2_stale_reconciliation'
        ),
        p_status := 'confirmed',
        p_allow_negative := false
      );
    END IF;

    UPDATE public.withdrawal_requests
    SET status = 'failed',
        processed_at = now(),
        notes = concat_ws(' | ', NULLIF(notes, ''), 'provider_request_not_created; saldo devolvido'),
        updated_at = now()
    WHERE id = v_withdrawal.id;

    v_reversed_withdrawals := v_reversed_withdrawals + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'failed_deposits', v_failed_deposits,
    'reversed_withdrawals', v_reversed_withdrawals,
    'ran_at', now()
  );
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_stale_wallet_v2_requests() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reconcile_stale_wallet_v2_requests() TO service_role;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (
      SELECT 1 FROM cron.job
      WHERE jobname = 'deligo-wallet-v2-stale-reconciliation'
    ) THEN
      PERFORM cron.unschedule('deligo-wallet-v2-stale-reconciliation');
    END IF;

    PERFORM cron.schedule(
      'deligo-wallet-v2-stale-reconciliation',
      '*/5 * * * *',
      $cron$SELECT public.reconcile_stale_wallet_v2_requests();$cron$
    );
  END IF;
END;
$$;
SELECT public.reconcile_stale_wallet_v2_requests();
COMMIT;
