-- Allow service_role to write audit tables used by app triggers
GRANT USAGE ON SCHEMA app TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO service_role;
