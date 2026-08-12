BEGIN;
UPDATE public.wallet_deposits
SET status = 'failed',
    provider_status = 'provider_unreachable_legacy',
    provider_payload = jsonb_build_object(
      'source', 'wallet_v2_reconciliation_2026_06_30',
      'reason', 'provider_dns_unavailable_and_transaction_expired',
      'transaction_id', transaction_id
    ),
    processed_at = now(),
    updated_at = now()
WHERE id = '50277999-63d6-4bb5-b351-8e47327d8fb8'
  AND status IN ('pending', 'processing')
  AND NOT EXISTS (
    SELECT 1
    FROM public.wallet_ledger wl
    WHERE wl.reference_key = 'deposit-net-' || wallet_deposits.id::text
      AND wl.status = 'confirmed'
  );
COMMIT;
