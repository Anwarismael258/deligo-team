BEGIN;
CREATE TABLE IF NOT EXISTS public.menu_item_likes (
  menu_item_id uuid NOT NULL REFERENCES public.menu_items(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (menu_item_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_menu_item_likes_item
  ON public.menu_item_likes(menu_item_id);
ALTER TABLE public.menu_item_likes ENABLE ROW LEVEL SECURITY;
CREATE POLICY menu_item_likes_read ON public.menu_item_likes
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY menu_item_likes_insert_own ON public.menu_item_likes
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY menu_item_likes_delete_own ON public.menu_item_likes
  FOR DELETE TO authenticated USING (user_id = auth.uid());
COMMIT;
