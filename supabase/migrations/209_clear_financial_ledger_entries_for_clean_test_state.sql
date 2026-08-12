BEGIN;
DO $$
BEGIN
  IF to_regclass('public.financial_ledger_entries') IS NULL THEN
    RETURN;
  END IF;

  ALTER TABLE public.financial_ledger_entries
    DISABLE TRIGGER trg_prevent_financial_ledger_delete;

  DELETE FROM public.financial_ledger_entries;

  ALTER TABLE public.financial_ledger_entries
    ENABLE TRIGGER trg_prevent_financial_ledger_delete;
END $$;
COMMIT;
