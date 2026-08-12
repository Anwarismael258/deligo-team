BEGIN;
DO $$
DECLARE
  v_user_id UUID;
  v_primary_wallet UUID;
  v_total_balance NUMERIC;
  v_total_available NUMERIC;
  v_total_pending NUMERIC;
BEGIN
  FOR v_user_id IN
    SELECT user_id
    FROM public.wallets
    WHERE user_id IS NOT NULL
    GROUP BY user_id
    HAVING COUNT(*) > 1
  LOOP
    SELECT id
    INTO v_primary_wallet
    FROM public.wallets
    WHERE user_id = v_user_id
    ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST, id DESC
    LIMIT 1;

    SELECT
      COALESCE(SUM(balance), 0),
      COALESCE(SUM(COALESCE(available_balance, balance, 0)), 0),
      COALESCE(SUM(COALESCE(pending_balance, 0)), 0)
    INTO
      v_total_balance,
      v_total_available,
      v_total_pending
    FROM public.wallets
    WHERE user_id = v_user_id;

    UPDATE public.wallets
    SET
      balance = v_total_balance,
      available_balance = v_total_available,
      pending_balance = v_total_pending,
      updated_at = NOW()
    WHERE id = v_primary_wallet;

    UPDATE public.wallet_deposits
    SET wallet_id = v_primary_wallet
    WHERE user_id = v_user_id
      AND wallet_id <> v_primary_wallet;

    UPDATE public.wallet_ledger
    SET wallet_id = v_primary_wallet
    WHERE user_id = v_user_id
      AND wallet_id IS NOT NULL
      AND wallet_id <> v_primary_wallet;

    DELETE FROM public.wallets
    WHERE user_id = v_user_id
      AND id <> v_primary_wallet;
  END LOOP;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS idx_wallets_user_id_unique
  ON public.wallets(user_id)
  WHERE user_id IS NOT NULL;
COMMIT;
