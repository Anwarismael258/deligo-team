-- Restore PostgREST visibility for the schemas used by Central HQ.
-- This changes API schema exposure only. It does not create, update, or delete data.
-- Table access remains governed by the existing grants and RLS policies.
ALTER ROLE authenticator SET pgrst.db_schemas =
  'public,graphql_public,storage,core,hq,deligo,sarca,taomoz,comunhao,mestre24,payments';

NOTIFY pgrst, 'reload config';
