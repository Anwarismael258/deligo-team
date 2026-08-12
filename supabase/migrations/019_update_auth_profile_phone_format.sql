-- Normalize phone to E.164 (+) in auth triggers to satisfy profiles_phone_e164_check

CREATE OR REPLACE FUNCTION public.auth_user_create_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_phone text;
BEGIN
  v_phone := COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone', '+258000000000');
  IF v_phone IS NOT NULL AND v_phone NOT LIKE '+%' THEN
    v_phone := '+' || v_phone;
  END IF;

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
    v_phone,
    COALESCE(NEW.raw_user_meta_data->>'role', 'client'),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.handle_user_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_phone text;
BEGIN
  v_phone := COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone', '+258000000000');
  IF v_phone IS NOT NULL AND v_phone NOT LIKE '+%' THEN
    v_phone := '+' || v_phone;
  END IF;

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
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'Novo Usuario'),
    v_phone,
    COALESCE(NEW.raw_user_meta_data->>'role', 'client'),
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$function$;
