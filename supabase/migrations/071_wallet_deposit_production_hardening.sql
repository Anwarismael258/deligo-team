ALTER TABLE IF EXISTS public.wallet_deposits
  ADD COLUMN IF NOT EXISTS gateway_fee NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS net_amount NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS provider_status TEXT,
  ADD COLUMN IF NOT EXISTS provider_payload JSONB;
UPDATE public.wallet_deposits
SET
  gateway_fee = COALESCE(gateway_fee, ROUND(COALESCE(amount, 0) * 0.05, 2)),
  net_amount = COALESCE(net_amount, ROUND(COALESCE(amount, 0) - (COALESCE(amount, 0) * 0.05), 2))
WHERE TRUE;
CREATE INDEX IF NOT EXISTS idx_wallet_deposits_reference ON public.wallet_deposits(reference);
CREATE INDEX IF NOT EXISTS idx_wallet_deposits_transaction_id ON public.wallet_deposits(transaction_id);
CREATE INDEX IF NOT EXISTS idx_wallet_deposits_status_created_at ON public.wallet_deposits(status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_wallet_ledger_deposit_net_unique
  ON public.wallet_ledger(entry_type, ((metadata->>'deposit_id')))
  WHERE entry_type = 'deposit_net';
CREATE UNIQUE INDEX IF NOT EXISTS idx_wallet_ledger_deposit_gateway_fee_unique
  ON public.wallet_ledger(entry_type, ((metadata->>'deposit_id')))
  WHERE entry_type = 'deposit_gateway_fee';
