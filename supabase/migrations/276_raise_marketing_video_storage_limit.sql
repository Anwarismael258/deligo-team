BEGIN;
UPDATE storage.buckets
SET file_size_limit = 104857600
WHERE id = 'restaurant-assets'
  AND COALESCE(file_size_limit, 0) < 104857600;
COMMIT;
