-- Add read receipt timestamps for chat messages
ALTER TABLE IF EXISTS public.messages
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ;
-- Mark messages as read for current user in a given order chat
CREATE OR REPLACE FUNCTION public.mark_messages_read(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.messages
  SET read_at = NOW()
  WHERE order_id = p_order_id
    AND sender_id <> auth.uid()
    AND read_at IS NULL;
END;
$$;
GRANT EXECUTE ON FUNCTION public.mark_messages_read(uuid) TO authenticated;
