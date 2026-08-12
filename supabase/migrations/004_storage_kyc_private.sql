-- 004_storage_kyc_private.sql
-- Enforce private KYC bucket and strict object policies.

BEGIN;
-- Ensure bucket exists and is private.
INSERT INTO storage.buckets (id, name, public)
VALUES ('kyc', 'kyc', false)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;
-- Drop legacy policies if present.
DROP POLICY IF EXISTS "kyc_select_own" ON storage.objects;
DROP POLICY IF EXISTS "kyc_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "kyc_update_own" ON storage.objects;
DROP POLICY IF EXISTS "kyc_delete_own" ON storage.objects;
DROP POLICY IF EXISTS "kyc_service_all" ON storage.objects;
-- Read own KYC files only.
CREATE POLICY "kyc_select_own"
ON storage.objects
FOR SELECT
USING (
  bucket_id = 'kyc'
  AND (
    name LIKE ('couriers/' || auth.uid()::text || '/%')
    OR auth.role() = 'service_role'
  )
);
-- Insert own KYC files only.
CREATE POLICY "kyc_insert_own"
ON storage.objects
FOR INSERT
WITH CHECK (
  bucket_id = 'kyc'
  AND (
    name LIKE ('couriers/' || auth.uid()::text || '/%')
    OR auth.role() = 'service_role'
  )
);
-- Update own KYC files only.
CREATE POLICY "kyc_update_own"
ON storage.objects
FOR UPDATE
USING (
  bucket_id = 'kyc'
  AND (
    name LIKE ('couriers/' || auth.uid()::text || '/%')
    OR auth.role() = 'service_role'
  )
)
WITH CHECK (
  bucket_id = 'kyc'
  AND (
    name LIKE ('couriers/' || auth.uid()::text || '/%')
    OR auth.role() = 'service_role'
  )
);
-- Delete own KYC files only.
CREATE POLICY "kyc_delete_own"
ON storage.objects
FOR DELETE
USING (
  bucket_id = 'kyc'
  AND (
    name LIKE ('couriers/' || auth.uid()::text || '/%')
    OR auth.role() = 'service_role'
  )
);
COMMIT;
