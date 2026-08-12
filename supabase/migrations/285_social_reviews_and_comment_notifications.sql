BEGIN;
ALTER TABLE public.menu_item_reviews
  ADD COLUMN IF NOT EXISTS is_pinned boolean NOT NULL DEFAULT false;
ALTER TABLE public.courier_reviews
  ADD COLUMN IF NOT EXISTS is_pinned boolean NOT NULL DEFAULT false;
CREATE TABLE IF NOT EXISTS public.social_review_replies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_type text NOT NULL CHECK (review_type IN ('menu_item', 'courier')),
  review_id uuid NOT NULL,
  author_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  author_name text NOT NULL DEFAULT 'Utilizador DeliGo',
  author_role text NOT NULL DEFAULT 'client',
  body text NOT NULL CHECK (char_length(trim(body)) BETWEEN 1 AND 1500),
  parent_reply_id uuid REFERENCES public.social_review_replies(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_social_review_replies_thread
  ON public.social_review_replies(review_type, review_id, created_at);
CREATE TABLE IF NOT EXISTS public.social_review_reply_likes (
  reply_id uuid NOT NULL REFERENCES public.social_review_replies(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (reply_id, user_id)
);
CREATE TABLE IF NOT EXISTS public.courier_review_likes (
  review_id uuid NOT NULL REFERENCES public.courier_reviews(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (review_id, user_id)
);
CREATE TABLE IF NOT EXISTS public.social_review_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_type text NOT NULL CHECK (review_type IN ('menu_item', 'courier', 'reply')),
  review_id uuid NOT NULL,
  reporter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK (char_length(trim(reason)) BETWEEN 3 AND 500),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (review_type, review_id, reporter_id)
);
ALTER TABLE public.social_review_replies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_review_reply_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courier_review_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_review_reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY social_review_replies_read ON public.social_review_replies
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY social_review_replies_write ON public.social_review_replies
  FOR INSERT TO authenticated WITH CHECK (author_id = auth.uid());
CREATE POLICY social_review_replies_delete ON public.social_review_replies
  FOR DELETE TO authenticated USING (author_id = auth.uid() OR public.is_admin());
CREATE POLICY social_review_reply_likes_read ON public.social_review_reply_likes
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY social_review_reply_likes_write ON public.social_review_reply_likes
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY social_review_reply_likes_delete ON public.social_review_reply_likes
  FOR DELETE TO authenticated USING (user_id = auth.uid());
CREATE POLICY courier_review_likes_read ON public.courier_review_likes
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY courier_review_likes_write ON public.courier_review_likes
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY courier_review_likes_delete ON public.courier_review_likes
  FOR DELETE TO authenticated USING (user_id = auth.uid());
CREATE POLICY social_review_reports_insert ON public.social_review_reports
  FOR INSERT TO authenticated WITH CHECK (reporter_id = auth.uid());
CREATE POLICY social_review_reports_read_own ON public.social_review_reports
  FOR SELECT TO authenticated USING (reporter_id = auth.uid() OR public.is_admin());
CREATE OR REPLACE FUNCTION public.set_social_review_pinned(
  p_review_type text,
  p_review_id uuid,
  p_pinned boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_review_type = 'menu_item' THEN
    IF NOT EXISTS (
      SELECT 1 FROM menu_item_reviews mr
      JOIN menu_items mi ON mi.id = mr.menu_item_id
      JOIN restaurants r ON r.id = mi.restaurant_id
      WHERE mr.id = p_review_id AND (r.owner_id = auth.uid() OR public.is_admin())
    ) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    UPDATE menu_item_reviews SET is_pinned = p_pinned WHERE id = p_review_id;
  ELSIF p_review_type = 'courier' THEN
    IF NOT EXISTS (
      SELECT 1 FROM courier_reviews cr
      WHERE cr.id = p_review_id AND (cr.courier_id = auth.uid() OR public.is_admin())
    ) THEN RAISE EXCEPTION 'not_allowed'; END IF;
    UPDATE courier_reviews SET is_pinned = p_pinned WHERE id = p_review_id;
  ELSE
    RAISE EXCEPTION 'invalid_review_type';
  END IF;
END;
$$;
CREATE OR REPLACE FUNCTION public.notify_restaurant_dish_comment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid;
  v_dish_name text;
BEGIN
  SELECT r.owner_id, mi.name INTO v_owner_id, v_dish_name
  FROM menu_items mi JOIN restaurants r ON r.id = mi.restaurant_id
  WHERE mi.id = NEW.menu_item_id;

  IF v_owner_id IS NOT NULL AND v_owner_id <> NEW.reviewer_id THEN
    PERFORM public.create_app_notification(
      v_owner_id,
      'REVIEW_RECEIVED',
      'Novo comentario no prato',
      COALESCE(NEW.reviewer_name, 'Um cliente') || ' comentou em "' || COALESCE(v_dish_name, 'Prato') || '".',
      'OPEN_REVIEW',
      NEW.id::text,
      'NORMAL',
      'restaurant',
      jsonb_build_object('review_id', NEW.id, 'review_type', 'menu_item', 'menu_item_id', NEW.menu_item_id)
    );
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_restaurant_dish_comment ON public.menu_item_reviews;
CREATE TRIGGER trg_notify_restaurant_dish_comment
AFTER INSERT ON public.menu_item_reviews
FOR EACH ROW EXECUTE FUNCTION public.notify_restaurant_dish_comment();
COMMIT;
