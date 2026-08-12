-- Set roles for known users by email and ensure profiles exist
-- Emails:
-- client: anwarismael258@gmail.com
-- admin: deligoentregas@gmail.com
-- restaurant: anis.justwork@gmail.com

WITH target AS (
  SELECT id, email
  FROM auth.users
  WHERE email IN (
    'anwarismael258@gmail.com',
    'deligoentregas@gmail.com',
    'anis.justwork@gmail.com'
  )
),
roles AS (
  SELECT id,
         email,
         CASE
           WHEN email = 'anwarismael258@gmail.com' THEN 'client'
           WHEN email = 'deligoentregas@gmail.com' THEN 'admin'
           WHEN email = 'anis.justwork@gmail.com' THEN 'restaurant'
           ELSE 'client'
         END AS role
  FROM target
)
UPDATE auth.users u
SET raw_user_meta_data = COALESCE(u.raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('role', r.role),
    raw_app_meta_data  = COALESCE(u.raw_app_meta_data, '{}'::jsonb)  || jsonb_build_object('role', r.role)
FROM roles r
WHERE u.id = r.id;
WITH target AS (
  SELECT id, email
  FROM auth.users
  WHERE email IN (
    'anwarismael258@gmail.com',
    'deligoentregas@gmail.com',
    'anis.justwork@gmail.com'
  )
),
roles AS (
  SELECT id,
         email,
         CASE
           WHEN email = 'anwarismael258@gmail.com' THEN 'client'
           WHEN email = 'deligoentregas@gmail.com' THEN 'admin'
           WHEN email = 'anis.justwork@gmail.com' THEN 'restaurant'
           ELSE 'client'
         END AS role
  FROM target
)
INSERT INTO public.profiles (id, full_name, phone, role, updated_at)
SELECT r.id,
       split_part(r.email, '@', 1) AS full_name,
       COALESCE(u.phone, '+258000000000') AS phone,
       r.role,
       now()
FROM roles r
JOIN auth.users u ON u.id = r.id
ON CONFLICT (id) DO UPDATE
SET role = EXCLUDED.role,
    full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
    phone = COALESCE(public.profiles.phone, EXCLUDED.phone),
    updated_at = now();
