-- Fix auth triggers to match current schema

-- Drop trigger that targets app.profiles (not used in this schema)
DROP TRIGGER IF EXISTS assign_default_role_trigger ON auth.users;
-- Create/replace profile creation function
CREATE OR REPLACE FUNCTION public.auth_user_create_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO public.profiles (
    id,
    full_name,
    phone,
    role,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone', '+258000000000'),
    COALESCE(NEW.raw_user_meta_data->>'role', 'client'),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$function$;
-- Ensure signup handler aligns with profiles schema
CREATE OR REPLACE FUNCTION public.handle_user_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO public.profiles (id, created_at, updated_at)
  VALUES (NEW.id, now(), now())
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$function$;
-- Fix wallet trigger to match wallets schema
CREATE OR REPLACE FUNCTION public.create_wallet_for_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.wallets w WHERE w.user_id = NEW.id) THEN
    INSERT INTO public.wallets (user_id, balance, currency)
    VALUES (NEW.id, 0, 'MZN');
  END IF;
  RETURN NEW;
END;
$function$;
