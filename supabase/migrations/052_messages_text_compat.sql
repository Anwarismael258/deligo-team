BEGIN;
ALTER TABLE IF EXISTS public.messages
  ADD COLUMN IF NOT EXISTS text TEXT DEFAULT '';
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'message'
  ) THEN
    EXECUTE $sql$
      UPDATE public.messages
      SET text = COALESCE(NULLIF(text, ''), message)
      WHERE COALESCE(NULLIF(text, ''), '') = '';
    $sql$;
  END IF;
END $$;
COMMIT;
