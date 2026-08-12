-- Auth user creation must not fail because a secondary public bootstrap row
-- hits a schema drift/constraint issue. Each section logs and continues.

CREATE OR REPLACE FUNCTION public.bootstrap_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_role TEXT := COALESCE(NEW.raw_user_meta_data ->> 'role', 'client');
  v_full_name TEXT := COALESCE(
    NEW.raw_user_meta_data ->> 'full_name',
    split_part(COALESCE(NEW.email, ''), '@', 1)
  );
  v_phone TEXT := COALESCE(NEW.raw_user_meta_data ->> 'phone', NEW.phone);
  v_public_role TEXT := CASE WHEN v_role = 'client' THEN 'customer' ELSE v_role END;
  v_kyc_status TEXT := CASE WHEN v_role = 'courier' THEN 'pending' ELSE 'approved' END;
BEGIN
  BEGIN
    IF to_regclass('public.users') IS NOT NULL THEN
      INSERT INTO public.users (id, role, name, phone, email, created_at)
      VALUES (NEW.id, v_public_role, v_full_name, v_phone, NEW.email, NOW())
      ON CONFLICT (id) DO UPDATE SET
        role = EXCLUDED.role,
        name = COALESCE(EXCLUDED.name, public.users.name),
        phone = COALESCE(EXCLUDED.phone, public.users.phone),
        email = COALESCE(EXCLUDED.email, public.users.email);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.user_trigger_errors (trigger_name, user_id, error_message, error_state)
    VALUES ('bootstrap_new_auth_user.users', NEW.id, SQLERRM, SQLSTATE);
  END;

  BEGIN
    IF to_regclass('public.profiles') IS NOT NULL THEN
      INSERT INTO public.profiles (
        id,
        user_id,
        full_name,
        phone,
        role,
        kyc_completed,
        kyc_status,
        staff_active,
        created_at,
        updated_at
      )
      VALUES (
        NEW.id,
        NEW.id,
        v_full_name,
        v_phone,
        v_role,
        CASE WHEN v_role = 'courier' THEN FALSE ELSE TRUE END,
        v_kyc_status,
        TRUE,
        NOW(),
        NOW()
      )
      ON CONFLICT (id) DO UPDATE SET
        user_id = EXCLUDED.user_id,
        full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
        phone = COALESCE(EXCLUDED.phone, public.profiles.phone),
        role = COALESCE(EXCLUDED.role, public.profiles.role),
        kyc_completed = COALESCE(EXCLUDED.kyc_completed, public.profiles.kyc_completed),
        kyc_status = COALESCE(EXCLUDED.kyc_status, public.profiles.kyc_status),
        staff_active = COALESCE(EXCLUDED.staff_active, public.profiles.staff_active),
        updated_at = NOW();
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.user_trigger_errors (trigger_name, user_id, error_message, error_state)
    VALUES ('bootstrap_new_auth_user.profiles', NEW.id, SQLERRM, SQLSTATE);
  END;

  BEGIN
    IF to_regclass('public.wallets') IS NOT NULL THEN
      INSERT INTO public.wallets (user_id, balance, currency, is_active, created_at, updated_at)
      VALUES (NEW.id, 0, 'MZN', TRUE, NOW(), NOW())
      ON CONFLICT (user_id) DO UPDATE SET
        updated_at = NOW();
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.user_trigger_errors (trigger_name, user_id, error_message, error_state)
    VALUES ('bootstrap_new_auth_user.wallets', NEW.id, SQLERRM, SQLSTATE);
  END;

  RETURN NEW;
END;
$$;
