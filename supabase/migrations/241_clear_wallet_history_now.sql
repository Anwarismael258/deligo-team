BEGIN;
DO $$
BEGIN
  IF to_regclass('public.wallet_ledger') IS NOT NULL THEN
    DELETE FROM public.wallet_ledger;
  END IF;

  IF to_regclass('public.wallet_deposits') IS NOT NULL THEN
    DELETE FROM public.wallet_deposits;
  END IF;
END $$;
COMMIT;
