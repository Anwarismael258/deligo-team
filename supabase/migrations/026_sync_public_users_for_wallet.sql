-- Ensure public.users is created before wallet insert (wallets.user_id FK)

CREATE OR REPLACE FUNCTION public.create_wallet_for_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_phone text;
  v_role text;
  v_name text;
BEGIN
  v_phone := COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone', NULL);
  IF v_phone IS NOT NULL AND v_phone NOT LIKE '+%' THEN
    v_phone := '+' || v_phone;
  END IF;

  v_role := COALESCE(NEW.raw_user_meta_data->>'role', 'client');
  IF v_role = 'client' THEN
    v_role := 'customer';
  END IF;

  v_name := COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1), 'User');

  BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = NEW.id) THEN
      INSERT INTO public.users (id, role, name, phone, email, created_at)
      VALUES (NEW.id, v_role, v_name, v_phone, NEW.email, now());
    END IF;

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
