-- DeliGo Marketing & Publicidade: staff role for marketing collaborators.

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
      'ambassador',
      'marketing_agent'
    )
  );
ALTER TABLE public.field_staff_invites
  DROP CONSTRAINT IF EXISTS field_staff_invites_role_check;
ALTER TABLE public.field_staff_invites
  ADD CONSTRAINT field_staff_invites_role_check
  CHECK (role IN ('admin', 'field_agent', 'support_agent', 'ambassador', 'marketing_agent'));
