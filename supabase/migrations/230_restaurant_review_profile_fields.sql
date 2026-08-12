BEGIN;
ALTER TABLE IF EXISTS public.reviews
  ADD COLUMN IF NOT EXISTS restaurant_id uuid,
  ADD COLUMN IF NOT EXISTS reviewer_name text,
  ADD COLUMN IF NOT EXISTS image_url text,
  ADD COLUMN IF NOT EXISTS food_rating integer CHECK (food_rating IS NULL OR (food_rating >= 1 AND food_rating <= 5)),
  ADD COLUMN IF NOT EXISTS packaging_rating integer CHECK (packaging_rating IS NULL OR (packaging_rating >= 1 AND packaging_rating <= 5)),
  ADD COLUMN IF NOT EXISTS preparation_rating integer CHECK (preparation_rating IS NULL OR (preparation_rating >= 1 AND preparation_rating <= 5)),
  ADD COLUMN IF NOT EXISTS service_rating integer CHECK (service_rating IS NULL OR (service_rating >= 1 AND service_rating <= 5));
UPDATE public.reviews r
SET restaurant_id = o.restaurant_id
FROM public.orders o
WHERE r.order_id = o.id
  AND r.restaurant_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_reviews_restaurant_id
  ON public.reviews(restaurant_id);
CREATE OR REPLACE FUNCTION public.submit_restaurant_review(
  p_order_id uuid,
  p_reviewer_id uuid,
  p_rating integer,
  p_comment text DEFAULT NULL,
  p_food_rating integer DEFAULT NULL,
  p_packaging_rating integer DEFAULT NULL,
  p_preparation_rating integer DEFAULT NULL,
  p_service_rating integer DEFAULT NULL,
  p_image_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order record;
  v_profile record;
  v_existing_id uuid;
  v_reviewer_name text := 'Cliente DeliGo';
  v_avg_rating numeric := 0;
BEGIN
  IF p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'invalid_rating';
  END IF;

  IF p_food_rating IS NOT NULL AND (p_food_rating < 1 OR p_food_rating > 5) THEN
    RAISE EXCEPTION 'invalid_food_rating';
  END IF;
  IF p_packaging_rating IS NOT NULL AND (p_packaging_rating < 1 OR p_packaging_rating > 5) THEN
    RAISE EXCEPTION 'invalid_packaging_rating';
  END IF;
  IF p_preparation_rating IS NOT NULL AND (p_preparation_rating < 1 OR p_preparation_rating > 5) THEN
    RAISE EXCEPTION 'invalid_preparation_rating';
  END IF;
  IF p_service_rating IS NOT NULL AND (p_service_rating < 1 OR p_service_rating > 5) THEN
    RAISE EXCEPTION 'invalid_service_rating';
  END IF;

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND COALESCE(client_id, customer_id) = p_reviewer_id
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'only_customer_can_review_restaurant';
  END IF;

  IF COALESCE(v_order.status, '') NOT IN ('delivered', 'completed', 'auto_completed') THEN
    RAISE EXCEPTION 'order_not_completed';
  END IF;

  SELECT role, full_name, name
  INTO v_profile
  FROM public.profiles
  WHERE id = p_reviewer_id
  LIMIT 1;

  IF COALESCE(v_profile.role, '') NOT IN ('client', 'customer') THEN
    RAISE EXCEPTION 'only_customer_role_can_review_restaurant';
  END IF;

  v_reviewer_name := COALESCE(NULLIF(v_profile.full_name, ''), NULLIF(v_profile.name, ''), v_reviewer_name);

  SELECT id
  INTO v_existing_id
  FROM public.reviews
  WHERE order_id = p_order_id
    AND reviewer_id = p_reviewer_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing_id IS NULL THEN
    INSERT INTO public.reviews (
      id,
      order_id,
      reviewer_id,
      reviewer_name,
      restaurant_id,
      rating,
      comment,
      image_url,
      food_rating,
      packaging_rating,
      preparation_rating,
      service_rating,
      created_at
    )
    VALUES (
      gen_random_uuid(),
      p_order_id,
      p_reviewer_id,
      v_reviewer_name,
      v_order.restaurant_id,
      p_rating,
      NULLIF(trim(COALESCE(p_comment, '')), ''),
      NULLIF(trim(COALESCE(p_image_url, '')), ''),
      COALESCE(p_food_rating, p_rating),
      COALESCE(p_packaging_rating, p_rating),
      COALESCE(p_preparation_rating, p_rating),
      COALESCE(p_service_rating, p_rating),
      now()
    );
  ELSE
    UPDATE public.reviews
    SET reviewer_name = v_reviewer_name,
        restaurant_id = v_order.restaurant_id,
        rating = p_rating,
        comment = NULLIF(trim(COALESCE(p_comment, '')), ''),
        image_url = NULLIF(trim(COALESCE(p_image_url, '')), ''),
        food_rating = COALESCE(p_food_rating, p_rating),
        packaging_rating = COALESCE(p_packaging_rating, p_rating),
        preparation_rating = COALESCE(p_preparation_rating, p_rating),
        service_rating = COALESCE(p_service_rating, p_rating),
        created_at = now()
    WHERE id = v_existing_id;
  END IF;

  SELECT COALESCE(AVG(rating::numeric), 0)
  INTO v_avg_rating
  FROM public.reviews
  WHERE restaurant_id = v_order.restaurant_id;

  UPDATE public.restaurants
  SET rating = ROUND(v_avg_rating::numeric, 2)
  WHERE id = v_order.restaurant_id;

  RETURN jsonb_build_object(
    'success', true,
    'restaurant_id', v_order.restaurant_id,
    'rating', p_rating
  );
END;
$$;
COMMIT;
