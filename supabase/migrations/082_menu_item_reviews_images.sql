BEGIN;
ALTER TABLE IF EXISTS public.menu_item_reviews
ADD COLUMN IF NOT EXISTS image_url text;
COMMIT;
