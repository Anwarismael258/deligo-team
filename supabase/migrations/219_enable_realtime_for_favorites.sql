DO $$
DECLARE
  v_publication_name constant text := 'supabase_realtime';
  v_table regclass := to_regclass('public.favorites');
BEGIN
  IF v_table IS NULL THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication
    WHERE pubname = v_publication_name
  ) THEN
    EXECUTE format('CREATE PUBLICATION %I', v_publication_name);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_rel pr
    JOIN pg_publication p ON p.oid = pr.prpubid
    WHERE p.pubname = v_publication_name
      AND pr.prrelid = v_table
  ) THEN
    EXECUTE format(
      'ALTER PUBLICATION %I ADD TABLE %s',
      v_publication_name,
      v_table::text
    );
  END IF;
END $$;
