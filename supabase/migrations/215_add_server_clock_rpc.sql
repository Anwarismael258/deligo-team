BEGIN;
CREATE OR REPLACE FUNCTION public.get_server_time()
RETURNS JSONB
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'server_time_utc',
    timezone('utc', now()),
    'timezone',
    'UTC'
  );
$$;
REVOKE ALL ON FUNCTION public.get_server_time() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_server_time() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_server_time() TO anon;
GRANT EXECUTE ON FUNCTION public.get_server_time() TO service_role;
COMMIT;
