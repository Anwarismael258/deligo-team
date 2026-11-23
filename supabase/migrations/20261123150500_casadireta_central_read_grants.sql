-- The Central reads CasaDireta through the server-side service role.
-- Keep CasaDireta's end-user RLS policies unchanged; this grant only allows
-- the trusted Central backend to perform its authorized read-only snapshot.
grant usage on schema casadireta to service_role;
grant select on table casadireta.properties to service_role;
