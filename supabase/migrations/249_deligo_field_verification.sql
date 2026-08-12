-- DeliGo Field: lightweight verification and operations workspace.

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (
    role IN (
      'client',
      'customer',
      'restaurant',
      'courier',
      'admin',
      'field_agent',
      'support_agent',
      'ambassador'
    )
  );
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS staff_access_level TEXT,
  ADD COLUMN IF NOT EXISTS staff_invited_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS staff_first_login_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS staff_active BOOLEAN NOT NULL DEFAULT TRUE;
CREATE OR REPLACE FUNCTION public.is_deligo_field_staff(allowed_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles staff
    WHERE staff.id = auth.uid()
      AND COALESCE(staff.staff_active, TRUE) IS TRUE
      AND staff.role = ANY(allowed_roles)
  );
$$;
REVOKE ALL ON FUNCTION public.is_deligo_field_staff(TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_deligo_field_staff(TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_deligo_field_staff(TEXT[]) TO service_role;
CREATE TABLE IF NOT EXISTS public.field_internal_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type TEXT NOT NULL CHECK (entity_type IN ('restaurant', 'courier', 'client', 'customer', 'user')),
  entity_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  note TEXT NOT NULL CHECK (length(trim(note)) > 0),
  created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.field_staff_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name TEXT NOT NULL CHECK (length(trim(full_name)) > 0),
  phone TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('admin', 'field_agent', 'support_agent', 'ambassador')),
  city TEXT,
  access_level TEXT,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  invited_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  invited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  accepted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  accepted_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_field_staff_invites_phone_active
  ON public.field_staff_invites(phone)
  WHERE active IS TRUE AND accepted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_field_internal_notes_entity
  ON public.field_internal_notes(entity_type, entity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_field_internal_notes_created_by
  ON public.field_internal_notes(created_by, created_at DESC);
ALTER TABLE public.field_internal_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_staff_invites ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS profiles_field_staff_select ON public.profiles;
CREATE POLICY profiles_field_staff_select
  ON public.profiles
  FOR SELECT
  TO authenticated
  USING (
    public.is_deligo_field_staff(
      ARRAY['admin', 'field_agent', 'support_agent', 'ambassador']
    )
  );
DROP POLICY IF EXISTS profiles_field_support_update ON public.profiles;
CREATE POLICY profiles_field_support_update
  ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (public.is_deligo_field_staff(ARRAY['admin', 'support_agent']))
  WITH CHECK (public.is_deligo_field_staff(ARRAY['admin', 'support_agent']));
DROP POLICY IF EXISTS admin_actions_log_field_staff_select ON public.admin_actions_log;
CREATE POLICY admin_actions_log_field_staff_select
  ON public.admin_actions_log
  FOR SELECT
  TO authenticated
  USING (
    public.is_deligo_field_staff(
      ARRAY['admin', 'field_agent', 'support_agent', 'ambassador']
    )
  );
DROP POLICY IF EXISTS admin_actions_log_field_staff_insert ON public.admin_actions_log;
CREATE POLICY admin_actions_log_field_staff_insert
  ON public.admin_actions_log
  FOR INSERT
  TO authenticated
  WITH CHECK (
    admin_id = auth.uid()
    AND public.is_deligo_field_staff(
      ARRAY['admin', 'field_agent', 'support_agent']
    )
  );
DROP POLICY IF EXISTS field_staff_invites_admin_all ON public.field_staff_invites;
CREATE POLICY field_staff_invites_admin_all
  ON public.field_staff_invites
  FOR ALL
  TO authenticated
  USING (public.is_deligo_field_staff(ARRAY['admin']))
  WITH CHECK (
    public.is_deligo_field_staff(ARRAY['admin'])
    AND (invited_by IS NULL OR invited_by = auth.uid())
  );
DROP POLICY IF EXISTS field_staff_invites_service_all ON public.field_staff_invites;
CREATE POLICY field_staff_invites_service_all
  ON public.field_staff_invites
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
DO $$
BEGIN
  IF to_regclass('public.couriers') IS NOT NULL THEN
    ALTER TABLE public.couriers ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS couriers_field_support_update ON public.couriers;
    CREATE POLICY couriers_field_support_update
      ON public.couriers
      FOR UPDATE
      TO authenticated
      USING (public.is_deligo_field_staff(ARRAY['admin', 'support_agent']))
      WITH CHECK (public.is_deligo_field_staff(ARRAY['admin', 'support_agent']));

    GRANT UPDATE ON public.couriers TO authenticated;
  END IF;
END $$;
DROP POLICY IF EXISTS field_notes_staff_select ON public.field_internal_notes;
CREATE POLICY field_notes_staff_select
  ON public.field_internal_notes
  FOR SELECT
  TO authenticated
  USING (
    public.is_deligo_field_staff(
      ARRAY['admin', 'field_agent', 'support_agent', 'ambassador']
    )
  );
DROP POLICY IF EXISTS field_notes_staff_insert ON public.field_internal_notes;
CREATE POLICY field_notes_staff_insert
  ON public.field_internal_notes
  FOR INSERT
  TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND public.is_deligo_field_staff(
      ARRAY['admin', 'field_agent', 'support_agent']
    )
  );
DROP POLICY IF EXISTS field_notes_service_all ON public.field_internal_notes;
CREATE POLICY field_notes_service_all
  ON public.field_internal_notes
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
GRANT SELECT, INSERT ON public.field_internal_notes TO authenticated;
GRANT ALL ON public.field_internal_notes TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.field_staff_invites TO authenticated;
GRANT ALL ON public.field_staff_invites TO service_role;
GRANT SELECT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT, INSERT ON public.admin_actions_log TO authenticated;
COMMENT ON TABLE public.field_internal_notes IS
  'Internal DeliGo Field notes visible only to DeliGo staff.';
COMMENT ON COLUMN public.profiles.staff_access_level IS
  'Optional staff access label for DeliGo Field workers.';
