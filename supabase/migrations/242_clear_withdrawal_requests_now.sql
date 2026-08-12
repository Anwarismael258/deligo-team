BEGIN;
DO $$
BEGIN
  IF to_regclass('public.withdrawal_requests') IS NOT NULL THEN
    DELETE FROM public.withdrawal_requests;
  END IF;
END $$;
COMMIT;
