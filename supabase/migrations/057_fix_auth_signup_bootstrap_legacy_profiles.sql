BEGIN;
CREATE OR REPLACE FUNCTION public.bootstrap_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_role TEXT := COALESCE(NEW.raw_user_meta_data ->> 'role', 'client');
  v_full_name TEXT := COALESCE(NEW.raw_user_meta_data ->> 'full_name', split_part(COALESCE(NEW.email, ''), '@', 1));
  v_phone TEXT := COALESCE(NEW.raw_user_meta_data ->> 'phone', NEW.phone);
  v_address TEXT := COALESCE(NEW.raw_user_meta_data ->> 'address', '');
  v_neighborhood TEXT := COALESCE(NEW.raw_user_meta_data ->> 'neighborhood', '');
  v_city TEXT := COALESCE(NEW.raw_user_meta_data ->> 'city', '');
  v_operator TEXT := COALESCE(NEW.raw_user_meta_data ->> 'mobile_operator', NULL);
  v_payment_method TEXT := COALESCE(NEW.raw_user_meta_data ->> 'preferred_payment_method', NULL);
  v_payment_contact TEXT := COALESCE(NEW.raw_user_meta_data ->> 'payment_contact', NULL);
  v_kyc_status TEXT := CASE WHEN v_role = 'courier' THEN 'pending' ELSE 'approved' END;
  v_address_udt TEXT;
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
      updated_at = NOW();

    SELECT c.udt_name
    INTO v_address_udt
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'profiles'
      AND c.column_name = 'address';

    IF v_address_udt = 'jsonb' AND NULLIF(v_address, '') IS NOT NULL THEN
      EXECUTE $sql$
        UPDATE public.profiles
        SET address = COALESCE(
          address,
          jsonb_build_object(
            'address', $2,
            'neighborhood', $3,
            'city', $4
          )
        ),
        updated_at = NOW()
        WHERE id = $1
      $sql$
      USING NEW.id, v_address, v_neighborhood, v_city;
    ELSIF v_address_udt IS NOT NULL AND NULLIF(v_address, '') IS NOT NULL THEN
      EXECUTE $sql$
        UPDATE public.profiles
        SET address = COALESCE(address, $2),
        updated_at = NOW()
        WHERE id = $1
      $sql$
      USING NEW.id, v_address;
    END IF;

    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'neighborhood'
    ) THEN
      UPDATE public.profiles
      SET neighborhood = COALESCE(NULLIF(neighborhood, ''), NULLIF(v_neighborhood, '')),
          updated_at = NOW()
      WHERE id = NEW.id;
    END IF;

    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'city'
    ) THEN
      UPDATE public.profiles
      SET city = COALESCE(NULLIF(city, ''), NULLIF(v_city, '')),
          updated_at = NOW()
      WHERE id = NEW.id;
    END IF;

    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'mobile_operator'
    ) THEN
      UPDATE public.profiles
      SET mobile_operator = COALESCE(mobile_operator, v_operator),
          updated_at = NOW()
      WHERE id = NEW.id;
    END IF;

    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'preferred_payment_method'
    ) THEN
      UPDATE public.profiles
      SET preferred_payment_method = COALESCE(preferred_payment_method, v_payment_method),
          updated_at = NOW()
      WHERE id = NEW.id;
    END IF;

    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'payment_contact'
    ) THEN
      UPDATE public.profiles
      SET payment_contact = COALESCE(payment_contact, v_payment_contact),
          updated_at = NOW()
      WHERE id = NEW.id;
    END IF;
  END IF;

  IF to_regclass('public.wallets') IS NOT NULL THEN
    INSERT INTO public.wallets (user_id, balance, currency, is_active, created_at, updated_at)
    VALUES (NEW.id, 0, 'MZN', TRUE, NOW(), NOW())
    ON CONFLICT (user_id) DO UPDATE SET
      updated_at = NOW();
  END IF;

  IF to_regclass('public.user_addresses') IS NOT NULL AND NULLIF(v_address, '') IS NOT NULL THEN
    INSERT INTO public.user_addresses (
      user_id,
      label,
      address,
      reference,
      delivery_instructions,
      neighborhood,
      city,
      is_default,
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      CASE WHEN v_role = 'restaurant' THEN 'Loja' ELSE 'Casa' END,
      v_address,
      v_neighborhood,
      CASE WHEN NULLIF(v_city, '') IS NULL THEN NULL ELSE 'Cidade: ' || v_city END,
      v_neighborhood,
      v_city,
      TRUE,
      NOW(),
      NOW()
    )
    ON CONFLICT DO NOTHING;
  END IF;

  IF v_role = 'restaurant' AND to_regclass('public.restaurants') IS NOT NULL THEN
    INSERT INTO public.restaurants (
      owner_id,
      name,
      description,
      phone,
      address,
      neighborhood,
      city,
      is_open,
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      v_full_name,
      'Parceiro DeliGo MZ',
      v_phone,
      v_address,
      v_neighborhood,
      v_city,
      TRUE,
      NOW(),
      NOW()
    )
    ON CONFLICT DO NOTHING;
  END IF;

  IF v_role = 'courier' AND to_regclass('public.couriers') IS NOT NULL THEN
    INSERT INTO public.couriers (
      id,
      full_name,
      phone,
      is_online,
      vehicle_type,
      rating,
      total_deliveries,
      earnings_today,
      acceptance_rate,
      cancellation_rate,
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      v_full_name,
      v_phone,
      FALSE,
      'motorbike',
      5.0,
      0,
      0,
      100,
      0,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
      full_name = COALESCE(EXCLUDED.full_name, public.couriers.full_name),
      phone = COALESCE(EXCLUDED.phone, public.couriers.phone),
      updated_at = NOW();
  END IF;

  RETURN NEW;
END;
$$;
COMMIT;
