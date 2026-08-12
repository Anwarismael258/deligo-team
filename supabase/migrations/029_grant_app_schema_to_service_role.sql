-- Allow service_role to execute app schema trigger functions
GRANT USAGE ON SCHEMA app TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO service_role;
