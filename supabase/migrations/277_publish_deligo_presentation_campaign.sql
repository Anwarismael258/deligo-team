BEGIN;
DO $$
DECLARE
  v_campaign_id UUID;
  v_creator_id UUID;
  v_cover_url TEXT := 'https://gfkptccbalpacyypptgl.supabase.co/storage/v1/object/public/restaurant-assets/platform/marketing/campaigns/apresentacao-deligo-cover.png';
  v_video_url TEXT := 'https://gfkptccbalpacyypptgl.supabase.co/storage/v1/object/public/restaurant-assets/platform/marketing/campaigns/apresentacao-deligo-mobile.mp4';
BEGIN
  SELECT id INTO v_creator_id
  FROM public.profiles
  WHERE role IN ('marketing_agent', 'admin')
  ORDER BY CASE WHEN role = 'marketing_agent' THEN 0 ELSE 1 END, created_at
  LIMIT 1;

  SELECT id INTO v_campaign_id
  FROM public.marketing_campaigns
  WHERE lower(title) = lower('Bem-vindo ao DeliGo')
    AND objective = 'internal_campaign'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_campaign_id IS NULL THEN
    INSERT INTO public.marketing_campaigns (
      created_by, title, subtitle, description, placement, campaign_type,
      type, objective, media_url, image_url, video_url, target_type,
      target_id, starts_at, ends_at, action_label, active, priority,
      budget, status, metadata
    ) VALUES (
      v_creator_id,
      'Bem-vindo ao DeliGo',
      'Apresentacao DeliGo',
      'Descubra tudo o que pode fazer no DeliGo: Delivery, Carteira Digital, Eventos, Compras, Pagamentos e muito mais.',
      'home_banner',
      'video',
      'deli',
      'internal_campaign',
      v_cover_url,
      v_cover_url,
      v_video_url,
      'internal_campaign',
      'home',
      now(),
      TIMESTAMPTZ '2026-07-10 23:59:59+02',
      'Explorar DeliGo',
      true,
      30,
      0,
      'published',
      jsonb_build_object(
        'campaign_name', 'Apresentacao DeliGo',
        'autoplay_on_home', true,
        'muted_by_default', true,
        'user_can_enable_audio', true,
        'splash_skip_seconds', 3,
        'once_per_session', true,
        'internet_required', true,
        'preload_on_wifi', true,
        'destination', 'internal_campaign',
        'action_type', 'close_and_stay_home',
        'video_duration_seconds', 44,
        'video_url', v_video_url
      )
    );
  ELSE
    UPDATE public.marketing_campaigns
    SET subtitle = 'Apresentacao DeliGo',
        description = 'Descubra tudo o que pode fazer no DeliGo: Delivery, Carteira Digital, Eventos, Compras, Pagamentos e muito mais.',
        placement = 'home_banner',
        campaign_type = 'video',
        type = 'deli',
        objective = 'internal_campaign',
        media_url = v_cover_url,
        image_url = v_cover_url,
        video_url = v_video_url,
        target_type = 'internal_campaign',
        target_id = 'home',
        starts_at = now(),
        ends_at = TIMESTAMPTZ '2026-07-10 23:59:59+02',
        action_label = 'Explorar DeliGo',
        active = true,
        priority = 30,
        status = 'published',
        metadata = jsonb_build_object(
          'campaign_name', 'Apresentacao DeliGo',
          'autoplay_on_home', true,
          'muted_by_default', true,
          'user_can_enable_audio', true,
          'splash_skip_seconds', 3,
          'once_per_session', true,
          'internet_required', true,
          'preload_on_wifi', true,
          'destination', 'internal_campaign',
          'action_type', 'close_and_stay_home',
          'video_duration_seconds', 44,
          'video_url', v_video_url
        ),
        updated_at = now()
    WHERE id = v_campaign_id;
  END IF;
END;
$$;
COMMIT;
