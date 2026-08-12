BEGIN;
CREATE TABLE IF NOT EXISTS public.courier_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  courier_id uuid NOT NULL,
  reviewer_id uuid NOT NULL,
  reviewer_name text,
  rating integer NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (order_id, reviewer_id)
);
CREATE INDEX IF NOT EXISTS idx_courier_reviews_courier_id
  ON public.courier_reviews(courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_reviews_order_id
  ON public.courier_reviews(order_id);
ALTER TABLE public.courier_reviews ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS courier_reviews_select_public ON public.courier_reviews;
CREATE POLICY courier_reviews_select_public
ON public.courier_reviews
FOR SELECT
TO anon, authenticated
USING (true);
DROP POLICY IF EXISTS courier_reviews_insert_customer_only ON public.courier_reviews;
CREATE POLICY courier_reviews_insert_customer_only
ON public.courier_reviews
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = reviewer_id);
DROP POLICY IF EXISTS courier_reviews_delete_own ON public.courier_reviews;
CREATE POLICY courier_reviews_delete_own
ON public.courier_reviews
FOR DELETE
TO authenticated
USING (auth.uid() = reviewer_id OR public.is_admin());
DROP POLICY IF EXISTS courier_reviews_service_all ON public.courier_reviews;
CREATE POLICY courier_reviews_service_all
ON public.courier_reviews
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);
CREATE OR REPLACE FUNCTION public.submit_courier_review(
  p_order_id uuid,
  p_reviewer_id uuid,
  p_rating integer,
  p_comment text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order record;
  v_profile record;
  v_reviewer_name text := 'Cliente DeliGo';
  v_avg_rating numeric := 0;
BEGIN
  IF p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'invalid_rating';
  END IF;

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND COALESCE(client_id, customer_id) = p_reviewer_id
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'only_customer_can_review_courier';
  END IF;

  IF v_order.courier_id IS NULL THEN
    RAISE EXCEPTION 'courier_not_assigned';
  END IF;

  IF COALESCE(v_order.status, '') NOT IN ('delivered', 'completed') THEN
    RAISE EXCEPTION 'order_not_completed';
  END IF;

  SELECT role, full_name, name
  INTO v_profile
  FROM public.profiles
  WHERE id = p_reviewer_id
  LIMIT 1;

  IF COALESCE(v_profile.role, '') NOT IN ('client', 'customer') THEN
    RAISE EXCEPTION 'only_customer_role_can_review_courier';
  END IF;

  v_reviewer_name := COALESCE(NULLIF(v_profile.full_name, ''), NULLIF(v_profile.name, ''), v_reviewer_name);

  INSERT INTO public.courier_reviews (
    order_id,
    courier_id,
    reviewer_id,
    reviewer_name,
    rating,
    comment
  )
  VALUES (
    p_order_id,
    v_order.courier_id,
    p_reviewer_id,
    v_reviewer_name,
    p_rating,
    NULLIF(trim(COALESCE(p_comment, '')), '')
  )
  ON CONFLICT (order_id, reviewer_id) DO UPDATE
  SET rating = EXCLUDED.rating,
      comment = EXCLUDED.comment,
      reviewer_name = EXCLUDED.reviewer_name,
      created_at = now();

  SELECT COALESCE(AVG(rating::numeric), 0)
  INTO v_avg_rating
  FROM public.courier_reviews
  WHERE courier_id = v_order.courier_id;

  UPDATE public.couriers
  SET rating = ROUND(v_avg_rating::numeric, 2),
      updated_at = now()
  WHERE id = v_order.courier_id;

  RETURN jsonb_build_object(
    'success', true,
    'courier_id', v_order.courier_id,
    'rating', p_rating
  );
END;
$$;
COMMIT;
