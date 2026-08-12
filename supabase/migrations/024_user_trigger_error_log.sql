-- Debug-friendly error logging for auth.user triggers (non-fatal)

CREATE TABLE IF NOT EXISTS public.user_trigger_errors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trigger_name text NOT NULL,
  user_id uuid,
  error_message text,
  error_state text,
  created_at timestamptz NOT NULL DEFAULT now()
);
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
      v_phone,
      COALESCE(NEW.raw_user_meta_data->>'role', 'client'),
      now(),
      now()
    )
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.user_trigger_errors (trigger_name, user_id, error_message, error_state)
    VALUES ('auth_user_create_profile', NEW.id, SQLERRM, SQLSTATE);
  END;

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
      COALESCE(NEW.raw_user_meta_data->>'full_name', 'Novo Usuario'),
      v_phone,
      COALESCE(NEW.raw_user_meta_data->>'role', 'client'),
      now(),
      now()
    )
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.user_trigger_errors (trigger_name, user_id, error_message, error_state)
    VALUES ('handle_user_signup', NEW.id, SQLERRM, SQLSTATE);
  END;

  RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.create_wallet_for_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.wallets w WHERE w.user_id = NEW.id) THEN
      INSERT INTO public.wallets (
        user_id,
        owner_id,
        balance,
        balance_bigint,
        locked_balance
      )
      VALUES (
        NEW.id,
        NEW.id,
        0,
        0,
        0
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.user_trigger_errors (trigger_name, user_id, error_message, error_state)
    VALUES ('create_wallet_for_user', NEW.id, SQLERRM, SQLSTATE);
  END;

  RETURN NEW;
END;
$function$;
