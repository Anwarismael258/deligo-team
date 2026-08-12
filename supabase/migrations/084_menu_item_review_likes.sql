BEGIN;
CREATE TABLE IF NOT EXISTS public.menu_item_review_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id uuid NOT NULL REFERENCES public.menu_item_reviews(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (review_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_menu_item_review_likes_review_id
ON public.menu_item_review_likes(review_id);
CREATE INDEX IF NOT EXISTS idx_menu_item_review_likes_user_id
ON public.menu_item_review_likes(user_id);
ALTER TABLE public.menu_item_review_likes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS menu_item_review_likes_select_public ON public.menu_item_review_likes;
CREATE POLICY menu_item_review_likes_select_public
ON public.menu_item_review_likes
FOR SELECT
USING (true);
DROP POLICY IF EXISTS menu_item_review_likes_insert_own ON public.menu_item_review_likes;
CREATE POLICY menu_item_review_likes_insert_own
ON public.menu_item_review_likes
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS menu_item_review_likes_delete_own ON public.menu_item_review_likes;
CREATE POLICY menu_item_review_likes_delete_own
ON public.menu_item_review_likes
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);
COMMIT;
