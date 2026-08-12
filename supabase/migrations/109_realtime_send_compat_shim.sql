BEGIN;
CREATE SCHEMA IF NOT EXISTS realtime;
CREATE OR REPLACE FUNCTION realtime.send(
  topic text,
  event text,
  payload jsonb,
  is_public boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN;
END;
$$;
COMMIT;
