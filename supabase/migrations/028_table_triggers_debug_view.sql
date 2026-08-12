-- Debug view to list triggers for key public tables
CREATE OR REPLACE VIEW public.table_triggers_debug AS
SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  t.tgname AS trigger_name,
  t.tgisinternal AS is_internal,
  pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public'
  AND c.relname IN ('orders','order_items','restaurants','menu_items','messages');
