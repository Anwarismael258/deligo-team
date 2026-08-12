-- Keep the DeliGo App campaign center in sync with published marketing events.

CREATE OR REPLACE FUNCTION public.sync_marketing_event_campaign()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_id UUID;
  v_image_url TEXT;
BEGIN
  IF NEW.status <> 'published' THEN
    RETURN NEW;
  END IF;

  v_image_url := COALESCE(NULLIF(trim(NEW.banner_url), ''), NULLIF(trim(NEW.poster_url), ''));

  SELECT id
  INTO v_existing_id
  FROM public.marketing_campaigns
  WHERE event_id = NEW.id
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_existing_id IS NULL THEN
    INSERT INTO public.marketing_campaigns (
      restaurant_id,
      event_id,
      created_by,
      title,
      subtitle,
      description,
      placement,
      campaign_type,
      starts_at,
      ends_at,
      image_url,
      action_label,
      active,
      priority,
      metadata
    )
    VALUES (
      NEW.restaurant_id,
      NEW.id,
      NULL,
      NEW.title,
      CASE
        WHEN NEW.sells_tickets THEN 'Bilhetes disponiveis no DeliGo'
        ELSE NEW.location
      END,
      NEW.description,
      CASE WHEN NEW.sells_tickets THEN 'tickets' ELSE 'events_today' END,
      CASE WHEN NEW.sells_tickets THEN 'ticket' ELSE 'event' END,
      COALESCE(NEW.published_at, now()),
      NULL,
      v_image_url,
      CASE WHEN NEW.sells_tickets THEN 'Comprar bilhete' ELSE 'Ver evento' END,
      TRUE,
      80,
      jsonb_build_object(
        'source', 'marketing_event_auto_campaign',
        'action_type', CASE WHEN NEW.sells_tickets THEN 'buy_ticket' ELSE 'open_event' END,
        'event_date', NEW.event_date,
        'event_time', NEW.event_time,
        'location', NEW.location
      )
    );
  ELSE
    UPDATE public.marketing_campaigns
    SET restaurant_id = NEW.restaurant_id,
        title = NEW.title,
        subtitle = CASE
          WHEN NEW.sells_tickets THEN 'Bilhetes disponiveis no DeliGo'
          ELSE NEW.location
        END,
        description = NEW.description,
        placement = CASE WHEN NEW.sells_tickets THEN 'tickets' ELSE 'events_today' END,
        campaign_type = CASE WHEN NEW.sells_tickets THEN 'ticket' ELSE 'event' END,
        image_url = v_image_url,
        action_label = CASE WHEN NEW.sells_tickets THEN 'Comprar bilhete' ELSE 'Ver evento' END,
        active = TRUE,
        priority = GREATEST(priority, 80),
        metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
          'source', 'marketing_event_auto_campaign',
          'action_type', CASE WHEN NEW.sells_tickets THEN 'buy_ticket' ELSE 'open_event' END,
          'event_date', NEW.event_date,
          'event_time', NEW.event_time,
          'location', NEW.location
        ),
        updated_at = now()
    WHERE id = v_existing_id;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_marketing_event_campaign ON public.marketing_events;
CREATE TRIGGER trg_sync_marketing_event_campaign
AFTER INSERT OR UPDATE OF status, title, description, poster_url, banner_url, sells_tickets, event_date, event_time, location
ON public.marketing_events
FOR EACH ROW
EXECUTE FUNCTION public.sync_marketing_event_campaign();
INSERT INTO public.marketing_campaigns (
  restaurant_id,
  event_id,
  created_by,
  title,
  subtitle,
  description,
  placement,
  campaign_type,
  starts_at,
  ends_at,
  image_url,
  action_label,
  active,
  priority,
  metadata
)
SELECT
  e.restaurant_id,
  e.id,
  NULL,
  e.title,
  CASE WHEN e.sells_tickets THEN 'Bilhetes disponiveis no DeliGo' ELSE e.location END,
  e.description,
  CASE WHEN e.sells_tickets THEN 'tickets' ELSE 'events_today' END,
  CASE WHEN e.sells_tickets THEN 'ticket' ELSE 'event' END,
  COALESCE(e.published_at, now()),
  NULL,
  COALESCE(NULLIF(trim(e.banner_url), ''), NULLIF(trim(e.poster_url), '')),
  CASE WHEN e.sells_tickets THEN 'Comprar bilhete' ELSE 'Ver evento' END,
  TRUE,
  80,
  jsonb_build_object(
    'source', 'marketing_event_auto_campaign',
    'action_type', CASE WHEN e.sells_tickets THEN 'buy_ticket' ELSE 'open_event' END,
    'event_date', e.event_date,
    'event_time', e.event_time,
    'location', e.location
  )
FROM public.marketing_events e
WHERE e.status = 'published'
  AND NOT EXISTS (
    SELECT 1
    FROM public.marketing_campaigns c
    WHERE c.event_id = e.id
  );
