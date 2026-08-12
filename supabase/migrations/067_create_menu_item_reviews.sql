CREATE TABLE IF NOT EXISTS public.menu_item_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_item_id uuid NOT NULL REFERENCES public.menu_items(id) ON DELETE CASCADE,
  reviewer_id uuid NOT NULL,
  reviewer_name text,
  rating integer NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_menu_item_reviews_menu_item_id
  ON public.menu_item_reviews(menu_item_id);
CREATE INDEX IF NOT EXISTS idx_menu_item_reviews_reviewer_id
  ON public.menu_item_reviews(reviewer_id);
ALTER TABLE public.menu_item_reviews ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS menu_item_reviews_select_public ON public.menu_item_reviews;
CREATE POLICY menu_item_reviews_select_public
ON public.menu_item_reviews
FOR SELECT
TO anon, authenticated
USING (true);
DROP POLICY IF EXISTS menu_item_reviews_insert_own ON public.menu_item_reviews;
CREATE POLICY menu_item_reviews_insert_own
ON public.menu_item_reviews
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = reviewer_id OR public.is_admin());
DROP POLICY IF EXISTS menu_item_reviews_update_own ON public.menu_item_reviews;
CREATE POLICY menu_item_reviews_update_own
ON public.menu_item_reviews
FOR UPDATE
TO authenticated
USING (auth.uid() = reviewer_id OR public.is_admin())
WITH CHECK (auth.uid() = reviewer_id OR public.is_admin());
DROP POLICY IF EXISTS menu_item_reviews_delete_own ON public.menu_item_reviews;
CREATE POLICY menu_item_reviews_delete_own
ON public.menu_item_reviews
FOR DELETE
TO authenticated
USING (auth.uid() = reviewer_id OR public.is_admin());
DROP POLICY IF EXISTS menu_item_reviews_service_all ON public.menu_item_reviews;
CREATE POLICY menu_item_reviews_service_all
ON public.menu_item_reviews
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);
