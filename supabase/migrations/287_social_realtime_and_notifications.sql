BEGIN;
DROP POLICY IF EXISTS social_review_reports_admin_update
  ON public.social_review_reports;
CREATE POLICY social_review_reports_admin_update
ON public.social_review_reports FOR UPDATE TO authenticated
USING (public.is_admin()) WITH CHECK (public.is_admin());
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.menu_item_likes;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.menu_item_reviews;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.social_review_replies;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.social_review_reply_likes;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.menu_item_review_likes;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.courier_review_likes;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
CREATE OR REPLACE FUNCTION public.notify_social_review_reply()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recipient uuid;
  v_title text;
BEGIN
  IF NEW.review_type = 'menu_item' THEN
    SELECT reviewer_id INTO v_recipient
    FROM menu_item_reviews WHERE id = NEW.review_id;
    v_title := 'Nova resposta ao seu comentario';
  ELSIF NEW.review_type = 'courier' THEN
    SELECT reviewer_id INTO v_recipient
    FROM courier_reviews WHERE id = NEW.review_id;
    v_title := 'Nova resposta sobre o estafeta';
  END IF;

  IF v_recipient IS NOT NULL AND v_recipient <> NEW.author_id THEN
    PERFORM public.create_app_notification(
      v_recipient, 'REVIEW_REPLY', v_title,
      NEW.author_name || ' respondeu: ' || left(NEW.body, 120),
      'OPEN_REVIEW', NEW.review_id::text, 'NORMAL', 'social',
      jsonb_build_object('review_id', NEW.review_id, 'review_type', NEW.review_type)
    );
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_social_review_reply ON public.social_review_replies;
CREATE TRIGGER trg_notify_social_review_reply
AFTER INSERT ON public.social_review_replies
FOR EACH ROW EXECUTE FUNCTION public.notify_social_review_reply();
CREATE OR REPLACE FUNCTION public.notify_menu_item_like()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid;
  v_name text;
  v_restaurant_id uuid;
BEGIN
  SELECT r.owner_id, mi.name, r.id INTO v_owner, v_name, v_restaurant_id
  FROM menu_items mi JOIN restaurants r ON r.id = mi.restaurant_id
  WHERE mi.id = NEW.menu_item_id;
  IF v_owner IS NOT NULL AND v_owner <> NEW.user_id THEN
    PERFORM public.create_app_notification(
      v_owner, 'DISH_LIKED', 'O seu prato recebeu um gosto',
      'Um cliente gostou de "' || COALESCE(v_name, 'Prato') || '".',
      'OPEN_DISH', NEW.menu_item_id::text, 'LOW', 'restaurant',
      jsonb_build_object(
        'menu_item_id', NEW.menu_item_id,
        'restaurant_id', v_restaurant_id
      )
    );
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_menu_item_like ON public.menu_item_likes;
CREATE TRIGGER trg_notify_menu_item_like
AFTER INSERT ON public.menu_item_likes
FOR EACH ROW EXECUTE FUNCTION public.notify_menu_item_like();
COMMIT;
