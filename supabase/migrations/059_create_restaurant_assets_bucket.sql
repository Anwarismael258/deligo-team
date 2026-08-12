DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM storage.buckets WHERE id = 'restaurant-assets'
  ) THEN
    INSERT INTO storage.buckets (id, name, public)
    VALUES ('restaurant-assets', 'restaurant-assets', true);
  END IF;
END $$;
DROP POLICY IF EXISTS "Public restaurant assets are readable" ON storage.objects;
CREATE POLICY "Public restaurant assets are readable"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'restaurant-assets');
DROP POLICY IF EXISTS "Owners can upload restaurant assets" ON storage.objects;
CREATE POLICY "Owners can upload restaurant assets"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'restaurant-assets'
  AND auth.uid()::text = split_part(name, '/', 1)
);
DROP POLICY IF EXISTS "Owners can update restaurant assets" ON storage.objects;
CREATE POLICY "Owners can update restaurant assets"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'restaurant-assets'
  AND auth.uid()::text = split_part(name, '/', 1)
)
WITH CHECK (
  bucket_id = 'restaurant-assets'
  AND auth.uid()::text = split_part(name, '/', 1)
);
DROP POLICY IF EXISTS "Owners can delete restaurant assets" ON storage.objects;
CREATE POLICY "Owners can delete restaurant assets"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'restaurant-assets'
  AND auth.uid()::text = split_part(name, '/', 1)
);
