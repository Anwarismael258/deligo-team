-- View to inspect trigger function definitions for auth.users triggers
CREATE OR REPLACE VIEW public.auth_users_trigger_functions AS
SELECT
  n.nspname AS schema,
  p.proname AS function_name,
  pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname IN (
  'assign_default_role',
  'auth_user_create_profile',
  'create_wallet_for_user',
  'handle_email_confirmed',
  'handle_user_signup'
);
