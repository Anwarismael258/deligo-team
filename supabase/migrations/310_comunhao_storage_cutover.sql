BEGIN;
-- Keep public media readable while restricting writes to authenticated owners.
DROP POLICY IF EXISTS "Comunhao public media read" ON storage.objects;
CREATE POLICY "Comunhao public media read"
ON storage.objects FOR SELECT
TO public
USING (
  bucket_id IN (
    'pastoral-publications',
    'community-media',
    'church-application-branding',
    'profile-media'
  )
);
DROP POLICY IF EXISTS "Comunhao authenticated media upload" ON storage.objects;
CREATE POLICY "Comunhao authenticated media upload"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id IN (
    'pastoral-publications',
    'community-media',
    'church-application-branding',
    'profile-media'
  )
);
DROP POLICY IF EXISTS "Comunhao owners update media" ON storage.objects;
CREATE POLICY "Comunhao owners update media"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id IN (
    'pastoral-publications',
    'community-media',
    'church-application-branding',
    'profile-media'
  )
  AND owner_id = auth.uid()::text
)
WITH CHECK (
  bucket_id IN (
    'pastoral-publications',
    'community-media',
    'church-application-branding',
    'profile-media'
  )
  AND owner_id = auth.uid()::text
);
DROP POLICY IF EXISTS "Comunhao owners delete media" ON storage.objects;
CREATE POLICY "Comunhao owners delete media"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id IN (
    'pastoral-publications',
    'community-media',
    'church-application-branding',
    'profile-media'
  )
  AND owner_id = auth.uid()::text
);
-- Replace every migrated public object URL with the central project host.
DO $cutover$
DECLARE
  column_item record;
BEGIN
  FOR column_item IN
    SELECT table_name, column_name
    FROM information_schema.columns
    WHERE table_schema = 'comunhao'
      AND data_type IN ('text', 'character varying')
  LOOP
    EXECUTE format(
      'UPDATE comunhao.%I
       SET %I = replace(%I, %L, %L)
       WHERE %I LIKE %L',
      column_item.table_name,
      column_item.column_name,
      column_item.column_name,
      'https://dxofxuajsrocbxdmekfx.supabase.co/storage/v1/object/public/',
      'https://tpmsgvkdjzoidvyiwwfk.supabase.co/storage/v1/object/public/',
      column_item.column_name,
      '%dxofxuajsrocbxdmekfx.supabase.co/storage/v1/object/public/%'
    );
  END LOOP;
END
$cutover$;
COMMIT;
