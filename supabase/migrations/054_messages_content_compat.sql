BEGIN;
ALTER TABLE IF EXISTS public.messages
  ADD COLUMN IF NOT EXISTS text TEXT,
  ADD COLUMN IF NOT EXISTS content TEXT DEFAULT '';
UPDATE public.messages
SET
  text = COALESCE(NULLIF(text, ''), content, ''),
  content = COALESCE(NULLIF(content, ''), text, '')
WHERE TRUE;
ALTER TABLE IF EXISTS public.messages
  ALTER COLUMN content SET DEFAULT '';
CREATE OR REPLACE FUNCTION public.sync_message_text_content()
RETURNS TRIGGER AS $$
BEGIN
  NEW.text := COALESCE(NULLIF(NEW.text, ''), NEW.content, '');
  NEW.content := COALESCE(NULLIF(NEW.content, ''), NEW.text, '');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_sync_message_text_content ON public.messages;
CREATE TRIGGER trg_sync_message_text_content
BEFORE INSERT OR UPDATE ON public.messages
FOR EACH ROW
EXECUTE FUNCTION public.sync_message_text_content();
COMMIT;
