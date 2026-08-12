-- Create avatars bucket and policies
-- Public read, authenticated users can manage own objects

INSERT INTO storage.buckets (id, name, public)
SELECT 'avatars', 'avatars', true
WHERE NOT EXISTS (
  SELECT 1 FROM storage.buckets WHERE id = 'avatars'
);
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Public avatars are readable'
  ) THEN
    EXECUTE 'CREATE POLICY "Public avatars are readable" ON storage.objects
      FOR SELECT USING (bucket_id = ''avatars'')';
  END IF;
END;
$$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Users can upload own avatars'
  ) THEN
    EXECUTE 'CREATE POLICY "Users can upload own avatars" ON storage.objects
      FOR INSERT WITH CHECK (bucket_id = ''avatars'' AND auth.uid() = owner)';
  END IF;
END;
$$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Users can update own avatars'
  ) THEN
    EXECUTE 'CREATE POLICY "Users can update own avatars" ON storage.objects
      FOR UPDATE USING (bucket_id = ''avatars'' AND auth.uid() = owner)';
  END IF;
END;
$$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Users can delete own avatars'
  ) THEN
    EXECUTE 'CREATE POLICY "Users can delete own avatars" ON storage.objects
      FOR DELETE USING (bucket_id = ''avatars'' AND auth.uid() = owner)';
  END IF;
END;
$$;
