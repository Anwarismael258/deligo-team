BEGIN;
ALTER TABLE public.marketing_campaigns
  ADD COLUMN IF NOT EXISTS type TEXT,
  ADD COLUMN IF NOT EXISTS objective TEXT,
  ADD COLUMN IF NOT EXISTS media_url TEXT,
  ADD COLUMN IF NOT EXISTS video_url TEXT,
  ADD COLUMN IF NOT EXISTS target_type TEXT,
  ADD COLUMN IF NOT EXISTS target_id TEXT,
  ADD COLUMN IF NOT EXISTS budget NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'published';
UPDATE public.marketing_campaigns
SET
  type = COALESCE(type, campaign_type),
  objective = COALESCE(objective, 'promotion'),
  media_url = COALESCE(media_url, image_url),
  target_type = COALESCE(
    target_type,
    CASE
      WHEN event_id IS NOT NULL THEN 'event'
      WHEN restaurant_id IS NOT NULL THEN 'restaurant'
      ELSE 'none'
    END
  ),
  target_id = COALESCE(target_id, event_id::text, restaurant_id::text),
  status = COALESCE(NULLIF(status, ''), CASE WHEN active THEN 'published' ELSE 'paused' END);
ALTER TABLE public.marketing_campaigns
  DROP CONSTRAINT IF EXISTS marketing_campaigns_placement_check;
ALTER TABLE public.marketing_campaigns
  ADD CONSTRAINT marketing_campaigns_placement_check
  CHECK (placement IN (
    'campaign_center',
    'home_banner',
    'secondary_banner',
    'daily_offer',
    'featured_restaurant',
    'events_today',
    'tickets',
    'smart_discovery',
    'seasonal',
    'feed',
    'category',
    'splash_screen',
    'video_ad',
    'push'
  ));
ALTER TABLE public.marketing_campaigns
  DROP CONSTRAINT IF EXISTS marketing_campaigns_campaign_type_check;
ALTER TABLE public.marketing_campaigns
  ADD CONSTRAINT marketing_campaigns_campaign_type_check
  CHECK (campaign_type IN (
    'coupon',
    'promotion',
    'daily_offer',
    'featured_restaurant',
    'event',
    'ticket',
    'banner',
    'news',
    'seasonal',
    'smart_discovery',
    'ad',
    'deli',
    'video',
    'sponsor',
    'push'
  ));
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'marketing_campaigns_status_check'
      AND conrelid = 'public.marketing_campaigns'::regclass
  ) THEN
    ALTER TABLE public.marketing_campaigns
      ADD CONSTRAINT marketing_campaigns_status_check
      CHECK (status IN ('draft', 'scheduled', 'published', 'paused', 'completed', 'cancelled'));
  END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.marketing_settings (
  id BOOLEAN PRIMARY KEY DEFAULT TRUE,
  home_banner_limit INTEGER NOT NULL DEFAULT 5,
  sponsored_limit INTEGER NOT NULL DEFAULT 10,
  featured_limit INTEGER NOT NULL DEFAULT 20,
  video_limit INTEGER NOT NULL DEFAULT 1,
  featured_restaurants_limit INTEGER NOT NULL DEFAULT 10,
  featured_products_limit INTEGER NOT NULL DEFAULT 10,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (id IS TRUE)
);
INSERT INTO public.marketing_settings (id)
VALUES (TRUE)
ON CONFLICT (id) DO NOTHING;
ALTER TABLE public.marketing_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS marketing_settings_staff_select ON public.marketing_settings;
CREATE POLICY marketing_settings_staff_select
ON public.marketing_settings
FOR SELECT
TO authenticated
USING (public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']));
DROP POLICY IF EXISTS marketing_settings_admin_update ON public.marketing_settings;
CREATE POLICY marketing_settings_admin_update
ON public.marketing_settings
FOR UPDATE
TO authenticated
USING (public.is_deligo_field_staff(ARRAY['admin']))
WITH CHECK (public.is_deligo_field_staff(ARRAY['admin']));
GRANT SELECT ON public.marketing_settings TO authenticated;
GRANT UPDATE ON public.marketing_settings TO authenticated;
GRANT ALL ON public.marketing_settings TO service_role;
COMMIT;
