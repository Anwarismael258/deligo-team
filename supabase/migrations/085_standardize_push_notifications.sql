BEGIN;
ALTER TABLE IF EXISTS public.push_notifications
ADD COLUMN IF NOT EXISTS type text;
ALTER TABLE IF EXISTS public.push_notifications
ADD COLUMN IF NOT EXISTS entity_id text;
ALTER TABLE IF EXISTS public.push_notifications
ADD COLUMN IF NOT EXISTS action text;
ALTER TABLE IF EXISTS public.push_notifications
ADD COLUMN IF NOT EXISTS priority text DEFAULT 'NORMAL';
ALTER TABLE IF EXISTS public.push_notifications
ADD COLUMN IF NOT EXISTS channel text DEFAULT 'system';
ALTER TABLE IF EXISTS public.push_notifications
ADD COLUMN IF NOT EXISTS read_at timestamptz;
ALTER TABLE IF EXISTS public.push_notifications
ADD COLUMN IF NOT EXISTS metadata jsonb DEFAULT '{}'::jsonb;
UPDATE public.push_notifications
SET
  type = COALESCE(type, 'SYSTEM_ALERT'),
  priority = COALESCE(priority, 'NORMAL'),
  channel = COALESCE(channel, 'system'),
  metadata = COALESCE(metadata, data, '{}'::jsonb)
WHERE type IS NULL
   OR priority IS NULL
   OR channel IS NULL
   OR metadata IS NULL;
CREATE INDEX IF NOT EXISTS idx_push_notifications_user_created_at
ON public.push_notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_push_notifications_type
ON public.push_notifications(type);
CREATE INDEX IF NOT EXISTS idx_push_notifications_read_at
ON public.push_notifications(read_at);
CREATE OR REPLACE FUNCTION public.create_app_notification(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_action text DEFAULT NULL,
  p_entity_id text DEFAULT NULL,
  p_priority text DEFAULT 'NORMAL',
  p_channel text DEFAULT 'system',
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.push_notifications (
    user_id,
    type,
    title,
    body,
    action,
    entity_id,
    priority,
    channel,
    data,
    metadata,
    created_at
  )
  VALUES (
    p_user_id,
    p_type,
    p_title,
    p_body,
    p_action,
    p_entity_id,
    p_priority,
    p_channel,
    p_metadata,
    p_metadata,
    now()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
COMMIT;
