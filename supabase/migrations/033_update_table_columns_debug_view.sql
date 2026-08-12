-- Update debug view to include app schema tables
CREATE OR REPLACE VIEW public.table_columns_debug AS
SELECT
  table_schema,
  table_name,
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema IN ('public','app');
