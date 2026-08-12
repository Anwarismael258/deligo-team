BEGIN;
INSERT INTO storage.buckets (id, name, public)
VALUES ('kyc', 'kyc', false)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;
DROP POLICY IF EXISTS "kyc_select_own" ON storage.objects;
DROP POLICY IF EXISTS "kyc_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "kyc_update_own" ON storage.objects;
DROP POLICY IF EXISTS "kyc_delete_own" ON storage.objects;
CREATE POLICY "kyc_select_own"
ON storage.objects
FOR SELECT
USING (
  bucket_id = 'kyc'
  AND (
    name LIKE ('courier/' || auth.uid()::text || '/%')
    OR name LIKE ('couriers/' || auth.uid()::text || '/%')
    OR name LIKE ('restaurant/' || auth.uid()::text || '/%')
    OR name LIKE ('restaurants/' || auth.uid()::text || '/%')
    OR auth.role() = 'service_role'
  )
);
CREATE POLICY "kyc_insert_own"
ON storage.objects
FOR INSERT
WITH CHECK (
  bucket_id = 'kyc'
  AND (
    name LIKE ('courier/' || auth.uid()::text || '/%')
    OR name LIKE ('couriers/' || auth.uid()::text || '/%')
    OR name LIKE ('restaurant/' || auth.uid()::text || '/%')
    OR name LIKE ('restaurants/' || auth.uid()::text || '/%')
    OR auth.role() = 'service_role'
  )
);
CREATE POLICY "kyc_update_own"
ON storage.objects
FOR UPDATE
USING (
  bucket_id = 'kyc'
  AND (
    name LIKE ('courier/' || auth.uid()::text || '/%')
    OR name LIKE ('couriers/' || auth.uid()::text || '/%')
    OR name LIKE ('restaurant/' || auth.uid()::text || '/%')
    OR name LIKE ('restaurants/' || auth.uid()::text || '/%')
    OR auth.role() = 'service_role'
  )
)
WITH CHECK (
  bucket_id = 'kyc'
  AND (
    name LIKE ('courier/' || auth.uid()::text || '/%')
    OR name LIKE ('couriers/' || auth.uid()::text || '/%')
    OR name LIKE ('restaurant/' || auth.uid()::text || '/%')
    OR name LIKE ('restaurants/' || auth.uid()::text || '/%')
    OR auth.role() = 'service_role'
  )
);
CREATE POLICY "kyc_delete_own"
ON storage.objects
FOR DELETE
USING (
  bucket_id = 'kyc'
  AND (
    name LIKE ('courier/' || auth.uid()::text || '/%')
    OR name LIKE ('couriers/' || auth.uid()::text || '/%')
    OR name LIKE ('restaurant/' || auth.uid()::text || '/%')
    OR name LIKE ('restaurants/' || auth.uid()::text || '/%')
    OR auth.role() = 'service_role'
  )
);
COMMIT;
