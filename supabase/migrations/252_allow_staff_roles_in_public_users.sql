-- Keep public.users role constraint aligned with profiles/field staff roles.

ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE public.users
  ADD CONSTRAINT users_role_check
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
