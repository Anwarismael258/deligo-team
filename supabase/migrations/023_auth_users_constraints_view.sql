-- Debug view to list constraints on auth.users
CREATE OR REPLACE VIEW public.auth_users_constraints AS
SELECT
  c.conname AS constraint_name,
  pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
JOIN pg_class t ON c.conrelid = t.oid
JOIN pg_namespace n ON t.relnamespace = n.oid
WHERE n.nspname = 'auth'
  AND t.relname = 'users';
