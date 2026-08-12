-- Temporary-safe catalog helper for diagnosing auth bootstrap constraints.

CREATE OR REPLACE FUNCTION public.debug_auth_bootstrap_catalog()
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT jsonb_build_object(
    'auth_user_public_triggers',
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'trigger_name', t.tgname,
          'function_schema', fn_ns.nspname,
          'function_name', p.proname,
          'definition', pg_get_triggerdef(t.oid)
        )
        ORDER BY t.tgname
      )
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace table_ns ON table_ns.oid = c.relnamespace
      JOIN pg_proc p ON p.oid = t.tgfoid
      JOIN pg_namespace fn_ns ON fn_ns.oid = p.pronamespace
      WHERE table_ns.nspname = 'auth'
        AND c.relname = 'users'
        AND NOT t.tgisinternal
    ), '[]'::jsonb),
    'constraints',
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'schema', n.nspname,
          'table', c.relname,
          'constraint_name', con.conname,
          'constraint_type', con.contype,
          'definition', pg_get_constraintdef(con.oid)
        )
        ORDER BY n.nspname, c.relname, con.conname
      )
      FROM pg_constraint con
      JOIN pg_class c ON c.oid = con.conrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname IN ('profiles', 'users', 'wallets')
    ), '[]'::jsonb),
    'bootstrap_function',
    (
      SELECT pg_get_functiondef(p.oid)
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = 'bootstrap_new_auth_user'
      LIMIT 1
    )
  );
$$;
GRANT EXECUTE ON FUNCTION public.debug_auth_bootstrap_catalog() TO service_role;
