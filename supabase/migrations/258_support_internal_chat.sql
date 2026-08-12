BEGIN;
CREATE TABLE IF NOT EXISTS public.support_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_source TEXT NOT NULL DEFAULT 'deligo_chat',
  external_id TEXT NULL,
  opened_by UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  opened_by_role TEXT NOT NULL DEFAULT 'client',
  customer_name TEXT NULL,
  customer_phone TEXT NULL,
  customer_email TEXT NULL,
  dispute_type TEXT NOT NULL DEFAULT 'support',
  reason TEXT NOT NULL DEFAULT 'Pedido de suporte',
  status TEXT NOT NULL DEFAULT 'open',
  assigned_to UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  resolution TEXT NULL,
  resolved_by UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  resolved_at TIMESTAMPTZ NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status_updated
  ON public.support_tickets(status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_tickets_source_updated
  ON public.support_tickets(external_source, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_tickets_assigned_to
  ON public.support_tickets(assigned_to, updated_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_support_tickets_source_external_unique
  ON public.support_tickets(external_source, external_id)
  WHERE external_id IS NOT NULL;
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS support_tickets_participant_select ON public.support_tickets;
CREATE POLICY support_tickets_participant_select
  ON public.support_tickets
  FOR SELECT
  TO authenticated
  USING (
    opened_by = auth.uid()
    OR assigned_to = auth.uid()
    OR public.is_deligo_field_staff(ARRAY['admin', 'support_agent'])
  );
DROP POLICY IF EXISTS support_tickets_staff_update ON public.support_tickets;
CREATE POLICY support_tickets_staff_update
  ON public.support_tickets
  FOR UPDATE
  TO authenticated
  USING (public.is_deligo_field_staff(ARRAY['admin', 'support_agent']))
  WITH CHECK (public.is_deligo_field_staff(ARRAY['admin', 'support_agent']));
DROP POLICY IF EXISTS support_tickets_owner_update ON public.support_tickets;
CREATE POLICY support_tickets_owner_update
  ON public.support_tickets
  FOR UPDATE
  TO authenticated
  USING (opened_by = auth.uid())
  WITH CHECK (opened_by = auth.uid());
DROP POLICY IF EXISTS support_tickets_participant_insert ON public.support_tickets;
CREATE POLICY support_tickets_participant_insert
  ON public.support_tickets
  FOR INSERT
  TO authenticated
  WITH CHECK (
    opened_by = auth.uid()
    OR public.is_deligo_field_staff(ARRAY['admin', 'support_agent'])
  );
DROP POLICY IF EXISTS support_tickets_service_all ON public.support_tickets;
CREATE POLICY support_tickets_service_all
  ON public.support_tickets
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE ON public.support_tickets TO authenticated;
GRANT ALL ON public.support_tickets TO service_role;
CREATE TABLE IF NOT EXISTS public.support_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id UUID NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_name TEXT NOT NULL DEFAULT '',
  sender_role TEXT NOT NULL DEFAULT 'client',
  text TEXT NOT NULL DEFAULT '',
  attachment_url TEXT NULL,
  attachment_type TEXT NULL,
  delivered_at TIMESTAMPTZ NULL,
  read_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_support_messages_ticket_created
  ON public.support_messages(ticket_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_support_messages_sender
  ON public.support_messages(sender_id, created_at DESC);
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS support_messages_participant_select ON public.support_messages;
CREATE POLICY support_messages_participant_select
  ON public.support_messages
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.support_tickets st
      WHERE st.id = ticket_id
        AND (
          st.opened_by = auth.uid()
          OR st.assigned_to = auth.uid()
          OR public.is_deligo_field_staff(ARRAY['admin', 'support_agent'])
        )
    )
  );
DROP POLICY IF EXISTS support_messages_participant_insert ON public.support_messages;
CREATE POLICY support_messages_participant_insert
  ON public.support_messages
  FOR INSERT
  TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.support_tickets st
      WHERE st.id = ticket_id
        AND (
          st.opened_by = auth.uid()
          OR st.assigned_to = auth.uid()
          OR public.is_deligo_field_staff(ARRAY['admin', 'support_agent'])
        )
    )
  );
DROP POLICY IF EXISTS support_messages_participant_update ON public.support_messages;
CREATE POLICY support_messages_participant_update
  ON public.support_messages
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.support_tickets st
      WHERE st.id = ticket_id
        AND (
          st.opened_by = auth.uid()
          OR st.assigned_to = auth.uid()
          OR public.is_deligo_field_staff(ARRAY['admin', 'support_agent'])
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.support_tickets st
      WHERE st.id = ticket_id
        AND (
          st.opened_by = auth.uid()
          OR st.assigned_to = auth.uid()
          OR public.is_deligo_field_staff(ARRAY['admin', 'support_agent'])
        )
    )
  );
DROP POLICY IF EXISTS support_messages_service_all ON public.support_messages;
CREATE POLICY support_messages_service_all
  ON public.support_messages
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE ON public.support_messages TO authenticated;
GRANT ALL ON public.support_messages TO service_role;
CREATE OR REPLACE FUNCTION public.mark_support_messages_read(p_ticket_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.support_messages
  SET read_at = NOW()
  WHERE ticket_id = p_ticket_id
    AND sender_id <> auth.uid()
    AND read_at IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.support_tickets st
      WHERE st.id = p_ticket_id
        AND (
          st.opened_by = auth.uid()
          OR st.assigned_to = auth.uid()
          OR public.is_deligo_field_staff(ARRAY['admin', 'support_agent'])
        )
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.mark_support_messages_read(uuid) TO authenticated;
COMMIT;
