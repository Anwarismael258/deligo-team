-- Central runtime visibility and inbox realtime.
-- Safe: changes PostgREST publication/config only; it does not mutate data.
ALTER ROLE authenticator SET pgrst.db_schemas =
  'public,graphql_public,storage,core,hq,deligo,sarca,taomoz,comunhao,mestre24,payments';
NOTIFY pgrst, 'reload config';

ALTER TABLE IF EXISTS public.inbox_messages REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.inbox_replies REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF to_regclass('public.inbox_messages') IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'inbox_messages'
    ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.inbox_messages;
  END IF;
  IF to_regclass('public.inbox_replies') IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'inbox_replies'
    ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.inbox_replies;
  END IF;
END $$;
