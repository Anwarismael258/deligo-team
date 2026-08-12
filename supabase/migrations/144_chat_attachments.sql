-- Add attachment metadata to messages
ALTER TABLE IF EXISTS public.messages
  ADD COLUMN IF NOT EXISTS attachment_url TEXT,
  ADD COLUMN IF NOT EXISTS attachment_type TEXT;
-- Create chat attachments bucket (public read)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM storage.buckets WHERE id = 'chat-attachments'
  ) THEN
    INSERT INTO storage.buckets (id, name, public)
    VALUES ('chat-attachments', 'chat-attachments', true);
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Public chat attachments are readable'
  ) THEN
    EXECUTE 'CREATE POLICY "Public chat attachments are readable" ON storage.objects
      FOR SELECT USING (bucket_id = ''chat-attachments'')';
  END IF;
END;
$$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Users can upload chat attachments'
  ) THEN
    EXECUTE 'CREATE POLICY "Users can upload chat attachments" ON storage.objects
      FOR INSERT WITH CHECK (
        bucket_id = ''chat-attachments'' AND auth.uid()::text = split_part(name, ''/'', 1)
      )';
  END IF;
END;
$$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Users can update chat attachments'
  ) THEN
    EXECUTE 'CREATE POLICY "Users can update chat attachments" ON storage.objects
      FOR UPDATE USING (
        bucket_id = ''chat-attachments'' AND auth.uid()::text = split_part(name, ''/'', 1)
      )
      WITH CHECK (
        bucket_id = ''chat-attachments'' AND auth.uid()::text = split_part(name, ''/'', 1)
      )';
  END IF;
END;
$$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Users can delete chat attachments'
  ) THEN
    EXECUTE 'CREATE POLICY "Users can delete chat attachments" ON storage.objects
      FOR DELETE USING (
        bucket_id = ''chat-attachments'' AND auth.uid()::text = split_part(name, ''/'', 1)
      )';
  END IF;
END;
$$;
