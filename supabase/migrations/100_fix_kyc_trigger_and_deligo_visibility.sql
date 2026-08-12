BEGIN;
CREATE OR REPLACE FUNCTION public.on_profile_verification_docs_changed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has_docs BOOLEAN := FALSE;
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  IF COALESCE(jsonb_typeof(NEW.kyc_docs), '') = 'object' THEN
    v_has_docs := EXISTS (
      SELECT 1
      FROM jsonb_each(COALESCE(NEW.kyc_docs, '{}'::jsonb))
      WHERE COALESCE(NULLIF(value::text, 'null'), '') <> ''
    );
  END IF;

  IF NEW.role IN ('restaurant', 'courier')
     AND v_has_docs
     AND (
       TG_OP = 'INSERT'
       OR NEW.kyc_docs IS DISTINCT FROM OLD.kyc_docs
       OR NEW.phone IS DISTINCT FROM OLD.phone
       OR NEW.full_name IS DISTINCT FROM OLD.full_name
     ) THEN
    PERFORM public.prepare_profile_verification(NEW.id);
  END IF;

  RETURN NEW;
END;
$$;
DO $$
DECLARE
  v_restaurant_owner_id uuid;
  v_restaurant_id uuid;
BEGIN
  SELECT id
  INTO v_restaurant_owner_id
  FROM auth.users
  WHERE email = 'anis.justwork@gmail.com'
  LIMIT 1;

  IF v_restaurant_owner_id IS NULL THEN
    RAISE NOTICE 'Seed 100 ignorado: owner do Deligo Restaurante nao encontrado.';
    RETURN;
  END IF;

  UPDATE public.profiles
  SET
    kyc_status = 'approved',
    kyc_completed = TRUE,
    auto_verified = FALSE,
    verification_decision_source = 'manual',
    updated_at = now()
  WHERE id = v_restaurant_owner_id;

  SELECT id
  INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_restaurant_owner_id
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1;

  IF v_restaurant_id IS NULL THEN
    RAISE NOTICE 'Seed 100 ignorado: restaurante Deligo nao encontrado.';
    RETURN;
  END IF;

  UPDATE public.restaurants
  SET
    is_open = TRUE,
    updated_at = now()
  WHERE id = v_restaurant_id;

  UPDATE public.menu_items
  SET
    is_available = TRUE,
    stock_quantity = CASE
      WHEN COALESCE(stock_quantity, 0) <= 0 THEN 12
      ELSE stock_quantity
    END,
    updated_at = now()
  WHERE restaurant_id = v_restaurant_id;

  RAISE NOTICE 'Seed 100 concluído. Deligo Restaurante visível para clientes.';
END $$;
COMMIT;
