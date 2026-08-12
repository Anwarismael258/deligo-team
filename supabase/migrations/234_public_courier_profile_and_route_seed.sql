BEGIN;
ALTER TABLE IF EXISTS public.couriers
  ADD COLUMN IF NOT EXISTS avatar_url TEXT;
INSERT INTO public.couriers (id, full_name, phone, avatar_url, updated_at)
SELECT
  p.id,
  NULLIF(BTRIM(p.full_name), ''),
  NULLIF(BTRIM(p.phone), ''),
  NULLIF(BTRIM(p.avatar_url), ''),
  NOW()
FROM public.profiles p
WHERE COALESCE(p.role, '') = 'courier'
  AND NOT EXISTS (
    SELECT 1
    FROM public.couriers c
    WHERE c.id = p.id
  );
UPDATE public.couriers c
SET
  full_name = COALESCE(NULLIF(BTRIM(p.full_name), ''), c.full_name),
  phone = COALESCE(NULLIF(BTRIM(p.phone), ''), c.phone),
  avatar_url = NULLIF(BTRIM(p.avatar_url), ''),
  updated_at = NOW()
FROM public.profiles p
WHERE p.id = c.id
  AND COALESCE(p.role, '') = 'courier'
  AND (
    COALESCE(NULLIF(BTRIM(c.full_name), ''), '') <>
      COALESCE(NULLIF(BTRIM(p.full_name), ''), COALESCE(NULLIF(BTRIM(c.full_name), ''), ''))
    OR COALESCE(NULLIF(BTRIM(c.phone), ''), '') <>
      COALESCE(NULLIF(BTRIM(p.phone), ''), COALESCE(NULLIF(BTRIM(c.phone), ''), ''))
    OR COALESCE(NULLIF(BTRIM(c.avatar_url), ''), '') <>
      COALESCE(NULLIF(BTRIM(p.avatar_url), ''), '')
  );
CREATE OR REPLACE FUNCTION public.sync_courier_public_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.role, '') <> 'courier' THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.couriers (
    id,
    full_name,
    phone,
    avatar_url,
    updated_at
  )
  VALUES (
    NEW.id,
    NULLIF(BTRIM(NEW.full_name), ''),
    NULLIF(BTRIM(NEW.phone), ''),
    NULLIF(BTRIM(NEW.avatar_url), ''),
    NOW()
  )
  ON CONFLICT (id) DO UPDATE
  SET
    full_name = COALESCE(
      NULLIF(BTRIM(EXCLUDED.full_name), ''),
      public.couriers.full_name
    ),
    phone = COALESCE(
      NULLIF(BTRIM(EXCLUDED.phone), ''),
      public.couriers.phone
    ),
    avatar_url = NULLIF(BTRIM(EXCLUDED.avatar_url), ''),
    updated_at = NOW();

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_courier_public_profile ON public.profiles;
CREATE TRIGGER trg_sync_courier_public_profile
AFTER INSERT OR UPDATE OF role, full_name, phone, avatar_url
ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.sync_courier_public_profile();
CREATE OR REPLACE FUNCTION public.courier_accept_delivery(
  p_order_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_order public.orders%rowtype;
  v_is_courier BOOLEAN := FALSE;
  v_pickup_latitude NUMERIC;
  v_pickup_longitude NUMERIC;
  v_current_latitude NUMERIC;
  v_current_longitude NUMERIC;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'user_not_authenticated';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = v_user_id
      AND p.role = 'courier'
  )
  INTO v_is_courier;

  IF NOT v_is_courier THEN
    RAISE EXCEPTION 'not_courier';
  END IF;

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF COALESCE(v_order.delivery_type, '') = 'pickup'
     OR COALESCE(v_order.delivery_fee, 0) <= 0 THEN
    RAISE EXCEPTION 'order_not_delivery';
  END IF;

  IF v_order.courier_id IS NOT NULL THEN
    RAISE EXCEPTION 'courier_already_assigned';
  END IF;

  IF v_order.status NOT IN ('accepted', 'preparing', 'ready') THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  UPDATE public.orders
  SET courier_id = v_user_id,
      status = 'courier_assigned',
      updated_at = NOW()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  SELECT r.latitude, r.longitude
  INTO v_pickup_latitude, v_pickup_longitude
  FROM public.restaurants r
  WHERE r.id = v_order.restaurant_id
  LIMIT 1;

  SELECT c.current_latitude, c.current_longitude
  INTO v_current_latitude, v_current_longitude
  FROM public.couriers c
  WHERE c.id = v_user_id
  LIMIT 1;

  INSERT INTO public.deliveries (
    order_id,
    courier_id,
    pickup_latitude,
    pickup_longitude,
    delivery_latitude,
    delivery_longitude,
    current_latitude,
    current_longitude,
    status,
    updated_at
  )
  VALUES (
    v_order.id,
    v_user_id,
    v_pickup_latitude,
    v_pickup_longitude,
    v_order.delivery_latitude,
    v_order.delivery_longitude,
    v_current_latitude,
    v_current_longitude,
    'courier_assigned',
    NOW()
  )
  ON CONFLICT (order_id) DO UPDATE
  SET courier_id = EXCLUDED.courier_id,
      pickup_latitude = COALESCE(EXCLUDED.pickup_latitude, public.deliveries.pickup_latitude),
      pickup_longitude = COALESCE(EXCLUDED.pickup_longitude, public.deliveries.pickup_longitude),
      delivery_latitude = COALESCE(EXCLUDED.delivery_latitude, public.deliveries.delivery_latitude),
      delivery_longitude = COALESCE(EXCLUDED.delivery_longitude, public.deliveries.delivery_longitude),
      current_latitude = COALESCE(EXCLUDED.current_latitude, public.deliveries.current_latitude),
      current_longitude = COALESCE(EXCLUDED.current_longitude, public.deliveries.current_longitude),
      status = 'courier_assigned',
      updated_at = NOW();

  RETURN to_jsonb(v_order);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.courier_accept_delivery(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.courier_accept_delivery(UUID) TO authenticated;
COMMIT;
