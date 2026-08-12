-- DeliGo Marketing & Publicidade: requests, approvals, events, tickets and event wallet.

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (
    role IN (
      'client',
      'customer',
      'restaurant',
      'courier',
      'admin',
      'field_agent',
      'support_agent',
      'ambassador',
      'marketing_agent'
    )
  );
ALTER TABLE public.field_staff_invites
  DROP CONSTRAINT IF EXISTS field_staff_invites_role_check;
ALTER TABLE public.field_staff_invites
  ADD CONSTRAINT field_staff_invites_role_check
  CHECK (role IN ('admin', 'field_agent', 'support_agent', 'ambassador', 'marketing_agent'));
DO $$
BEGIN
  IF to_regclass('public.users') IS NOT NULL THEN
    ALTER TABLE public.users
      DROP CONSTRAINT IF EXISTS users_role_check;

    ALTER TABLE public.users
      ADD CONSTRAINT users_role_check
      CHECK (
        role IN (
          'client',
          'customer',
          'restaurant',
          'courier',
          'admin',
          'field_agent',
          'support_agent',
          'ambassador',
          'marketing_agent'
        )
      );
  END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.marketing_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  requested_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  request_type TEXT NOT NULL CHECK (
    request_type IN (
      'live_music',
      'karaoke',
      'dj_party',
      'happy_hour',
      'special_buffet',
      'theme_party',
      'sports_event',
      'cultural_event',
      'corporate_event',
      'other',
      'ad_campaign',
      'promotion',
      'restaurant_of_day'
    )
  ),
  event_name TEXT NOT NULL CHECK (length(trim(event_name)) > 0),
  description TEXT NOT NULL CHECK (length(trim(description)) > 0),
  event_date DATE NOT NULL,
  event_time TIME NOT NULL,
  location TEXT NOT NULL CHECK (length(trim(location)) > 0),
  objective TEXT NOT NULL DEFAULT 'increase_sales'
    CHECK (objective IN ('increase_sales', 'promote_restaurant', 'launch_product', 'attract_customers', 'loyalty')),
  target_audience TEXT NOT NULL DEFAULT 'all'
    CHECK (target_audience IN ('young', 'adults', 'families', 'companies', 'all')),
  age_rating TEXT NOT NULL DEFAULT 'free'
    CHECK (age_rating IN ('free', '16', '18', '21')),
  logo_url TEXT,
  photo_urls TEXT[] NOT NULL DEFAULT '{}',
  brand_colors TEXT,
  social_links TEXT,
  website TEXT,
  sells_tickets BOOLEAN NOT NULL DEFAULT FALSE,
  ticket_price NUMERIC(12,2),
  ticket_quantity INTEGER,
  sales_start_at TIMESTAMPTZ,
  sales_end_at TIMESTAMPTZ,
  notes TEXT,
  campaign_title TEXT,
  campaign_description TEXT,
  poster_url TEXT,
  banner_url TEXT,
  revision_notes TEXT,
  sla_due_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '48 hours'),
  status TEXT NOT NULL DEFAULT 'received'
    CHECK (status IN ('received', 'in_design', 'ready_for_restaurant_review', 'revision_requested', 'approved', 'published', 'cancelled', 'rejected')),
  restaurant_approved_at TIMESTAMPTZ,
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (
    sells_tickets IS FALSE
    OR (
      ticket_price IS NOT NULL
      AND ticket_price > 0
      AND ticket_quantity IS NOT NULL
      AND ticket_quantity > 0
    )
  )
);
CREATE TABLE IF NOT EXISTS public.marketing_request_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.marketing_requests(id) ON DELETE CASCADE,
  actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  from_status TEXT,
  to_status TEXT NOT NULL,
  note TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.marketing_request_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID NOT NULL REFERENCES public.marketing_requests(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('restaurant', 'marketing_agent', 'admin')),
  body TEXT NOT NULL CHECK (length(trim(body)) > 0),
  attachment_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.marketing_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID REFERENCES public.marketing_requests(id) ON DELETE SET NULL,
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  asset_type TEXT NOT NULL CHECK (asset_type IN ('poster', 'flyer', 'story', 'video', 'logo', 'banner', 'social_post')),
  title TEXT NOT NULL,
  file_url TEXT NOT NULL,
  thumbnail_url TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.marketing_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID UNIQUE REFERENCES public.marketing_requests(id) ON DELETE SET NULL,
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  event_type TEXT NOT NULL,
  event_date DATE NOT NULL,
  event_time TIME NOT NULL,
  location TEXT NOT NULL,
  poster_url TEXT,
  banner_url TEXT,
  sells_tickets BOOLEAN NOT NULL DEFAULT FALSE,
  ticket_price NUMERIC(12,2),
  ticket_quantity INTEGER,
  tickets_sold INTEGER NOT NULL DEFAULT 0,
  tickets_used INTEGER NOT NULL DEFAULT 0,
  gross_revenue NUMERIC(12,2) NOT NULL DEFAULT 0,
  deligo_commission NUMERIC(12,2) NOT NULL DEFAULT 0,
  net_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  qr_code_seed TEXT NOT NULL DEFAULT md5(random()::text || clock_timestamp()::text),
  status TEXT NOT NULL DEFAULT 'published'
    CHECK (status IN ('draft', 'published', 'completed', 'cancelled')),
  published_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.restaurant_event_wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  event_id UUID REFERENCES public.marketing_events(id) ON DELETE CASCADE,
  balance NUMERIC(12,2) NOT NULL DEFAULT 0,
  available_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
  pending_balance NUMERIC(12,2) NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'MZN',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (restaurant_id, event_id)
);
CREATE TABLE IF NOT EXISTS public.marketing_event_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.marketing_events(id) ON DELETE CASCADE,
  buyer_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ticket_code TEXT NOT NULL UNIQUE DEFAULT upper(substr(md5(random()::text || clock_timestamp()::text), 1, 10)),
  qr_code TEXT NOT NULL UNIQUE DEFAULT md5(random()::text || clock_timestamp()::text),
  price NUMERIC(12,2) NOT NULL,
  deligo_commission NUMERIC(12,2) NOT NULL,
  restaurant_amount NUMERIC(12,2) NOT NULL,
  status TEXT NOT NULL DEFAULT 'available'
    CHECK (status IN ('available', 'sold', 'used', 'cancelled')),
  sold_at TIMESTAMPTZ,
  used_at TIMESTAMPTZ,
  validated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  validation_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.marketing_event_metrics (
  event_id UUID PRIMARY KEY REFERENCES public.marketing_events(id) ON DELETE CASCADE,
  views INTEGER NOT NULL DEFAULT 0,
  clicks INTEGER NOT NULL DEFAULT 0,
  favorites INTEGER NOT NULL DEFAULT 0,
  shares INTEGER NOT NULL DEFAULT 0,
  conversion_rate NUMERIC(8,4) NOT NULL DEFAULT 0,
  occupancy_rate NUMERIC(8,4) NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.marketing_event_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.marketing_events(id) ON DELETE CASCADE,
  report_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  pdf_url TEXT,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.marketing_campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID REFERENCES public.restaurants(id) ON DELETE SET NULL,
  event_id UUID REFERENCES public.marketing_events(id) ON DELETE SET NULL,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  title TEXT NOT NULL CHECK (length(trim(title)) > 0),
  subtitle TEXT,
  description TEXT,
  placement TEXT NOT NULL DEFAULT 'campaign_center'
    CHECK (placement IN ('campaign_center', 'home_banner', 'daily_offer', 'featured_restaurant', 'events_today', 'tickets', 'smart_discovery', 'seasonal')),
  campaign_type TEXT NOT NULL DEFAULT 'promotion'
    CHECK (campaign_type IN ('coupon', 'promotion', 'daily_offer', 'featured_restaurant', 'event', 'ticket', 'banner', 'news', 'seasonal', 'smart_discovery')),
  coupon_code TEXT,
  discount_type TEXT CHECK (discount_type IN ('fixed_amount', 'percent', 'free_delivery')),
  discount_value NUMERIC(12,2),
  starts_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ends_at TIMESTAMPTZ,
  image_url TEXT,
  action_label TEXT NOT NULL DEFAULT 'Ver agora',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  priority INTEGER NOT NULL DEFAULT 0,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  views INTEGER NOT NULL DEFAULT 0,
  clicks INTEGER NOT NULL DEFAULT 0,
  conversions INTEGER NOT NULL DEFAULT 0,
  revenue_generated NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (coupon_code)
);
CREATE TABLE IF NOT EXISTS public.marketing_coupon_redemptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id UUID NOT NULL REFERENCES public.marketing_campaigns(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  coupon_code TEXT NOT NULL,
  discount_type TEXT NOT NULL,
  discount_value NUMERIC(12,2),
  status TEXT NOT NULL DEFAULT 'reserved'
    CHECK (status IN ('reserved', 'used', 'expired', 'cancelled')),
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (campaign_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_marketing_requests_restaurant_status
  ON public.marketing_requests(restaurant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_marketing_requests_status_sla
  ON public.marketing_requests(status, sla_due_at);
CREATE INDEX IF NOT EXISTS idx_marketing_events_restaurant_date
  ON public.marketing_events(restaurant_id, event_date);
CREATE INDEX IF NOT EXISTS idx_marketing_tickets_event_status
  ON public.marketing_event_tickets(event_id, status);
CREATE INDEX IF NOT EXISTS idx_marketing_assets_restaurant_type
  ON public.marketing_assets(restaurant_id, asset_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_marketing_campaigns_active_placement
  ON public.marketing_campaigns(active, placement, starts_at, ends_at, priority DESC);
CREATE INDEX IF NOT EXISTS idx_marketing_campaigns_restaurant
  ON public.marketing_campaigns(restaurant_id, active, created_at DESC);
CREATE OR REPLACE FUNCTION public.touch_marketing_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_marketing_requests_updated_at ON public.marketing_requests;
CREATE TRIGGER trg_marketing_requests_updated_at
  BEFORE UPDATE ON public.marketing_requests
  FOR EACH ROW EXECUTE FUNCTION public.touch_marketing_updated_at();
DROP TRIGGER IF EXISTS trg_marketing_events_updated_at ON public.marketing_events;
CREATE TRIGGER trg_marketing_events_updated_at
  BEFORE UPDATE ON public.marketing_events
  FOR EACH ROW EXECUTE FUNCTION public.touch_marketing_updated_at();
DROP TRIGGER IF EXISTS trg_marketing_campaigns_updated_at ON public.marketing_campaigns;
CREATE TRIGGER trg_marketing_campaigns_updated_at
  BEFORE UPDATE ON public.marketing_campaigns
  FOR EACH ROW EXECUTE FUNCTION public.touch_marketing_updated_at();
CREATE OR REPLACE FUNCTION public.log_marketing_request_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.marketing_request_history (
      request_id, actor_id, from_status, to_status, note
    )
    VALUES (NEW.id, auth.uid(), NULL, NEW.status, 'Pedido recebido');
    RETURN NEW;
  END IF;

  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO public.marketing_request_history (
      request_id, actor_id, from_status, to_status, note,
      metadata
    )
    VALUES (
      NEW.id,
      auth.uid(),
      OLD.status,
      NEW.status,
      NEW.revision_notes,
      jsonb_build_object('source', 'marketing_workflow')
    );
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_marketing_request_status_history ON public.marketing_requests;
CREATE TRIGGER trg_marketing_request_status_history
  AFTER INSERT OR UPDATE ON public.marketing_requests
  FOR EACH ROW EXECUTE FUNCTION public.log_marketing_request_status_change();
CREATE OR REPLACE FUNCTION public.approve_marketing_request_and_publish(
  p_request_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.marketing_requests%ROWTYPE;
  v_event_id UUID;
  v_owner_id UUID;
BEGIN
  SELECT *
  INTO v_request
  FROM public.marketing_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'marketing_request_not_found';
  END IF;

  SELECT owner_id
  INTO v_owner_id
  FROM public.restaurants
  WHERE id = v_request.restaurant_id;

  IF auth.uid() IS DISTINCT FROM v_owner_id
     AND NOT public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']) THEN
    RAISE EXCEPTION 'not_allowed_to_publish_marketing_request';
  END IF;

  INSERT INTO public.marketing_events (
    request_id,
    restaurant_id,
    title,
    description,
    event_type,
    event_date,
    event_time,
    location,
    poster_url,
    banner_url,
    sells_tickets,
    ticket_price,
    ticket_quantity,
    status,
    published_at
  )
  VALUES (
    v_request.id,
    v_request.restaurant_id,
    COALESCE(NULLIF(trim(v_request.campaign_title), ''), v_request.event_name),
    COALESCE(NULLIF(trim(v_request.campaign_description), ''), v_request.description),
    v_request.request_type,
    v_request.event_date,
    v_request.event_time,
    v_request.location,
    v_request.poster_url,
    v_request.banner_url,
    v_request.sells_tickets,
    v_request.ticket_price,
    v_request.ticket_quantity,
    'published',
    now()
  )
  ON CONFLICT (request_id) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    poster_url = EXCLUDED.poster_url,
    banner_url = EXCLUDED.banner_url,
    updated_at = now()
  RETURNING id INTO v_event_id;

  INSERT INTO public.restaurant_event_wallets (restaurant_id, event_id)
  VALUES (v_request.restaurant_id, v_event_id)
  ON CONFLICT (restaurant_id, event_id) DO NOTHING;

  INSERT INTO public.marketing_event_metrics (event_id)
  VALUES (v_event_id)
  ON CONFLICT (event_id) DO NOTHING;

  UPDATE public.marketing_requests
  SET status = 'published',
      restaurant_approved_at = COALESCE(restaurant_approved_at, now()),
      published_at = COALESCE(published_at, now())
  WHERE id = p_request_id;

  INSERT INTO public.marketing_request_messages (
    request_id, sender_id, sender_role, body
  )
  VALUES (
    p_request_id,
    COALESCE(auth.uid(), v_owner_id),
    CASE WHEN auth.uid() = v_owner_id THEN 'restaurant' ELSE 'marketing_agent' END,
    'O evento foi aprovado e publicado automaticamente na DeliGo.'
  );

  RETURN v_event_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.sell_marketing_event_ticket(
  p_event_id UUID,
  p_buyer_id UUID DEFAULT auth.uid()
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event public.marketing_events%ROWTYPE;
  v_ticket_id UUID;
  v_commission NUMERIC(12,2);
  v_restaurant_amount NUMERIC(12,2);
BEGIN
  SELECT *
  INTO v_event
  FROM public.marketing_events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND OR v_event.status <> 'published' OR v_event.sells_tickets IS FALSE THEN
    RAISE EXCEPTION 'event_not_available_for_ticket_sale';
  END IF;

  IF v_event.ticket_quantity IS NOT NULL AND v_event.tickets_sold >= v_event.ticket_quantity THEN
    RAISE EXCEPTION 'event_sold_out';
  END IF;

  v_commission := round((COALESCE(v_event.ticket_price, 0) * 0.10)::numeric, 2);
  v_restaurant_amount := round((COALESCE(v_event.ticket_price, 0) - v_commission)::numeric, 2);

  INSERT INTO public.marketing_event_tickets (
    event_id,
    buyer_id,
    price,
    deligo_commission,
    restaurant_amount,
    status,
    sold_at
  )
  VALUES (
    p_event_id,
    p_buyer_id,
    COALESCE(v_event.ticket_price, 0),
    v_commission,
    v_restaurant_amount,
    'sold',
    now()
  )
  RETURNING id INTO v_ticket_id;

  UPDATE public.marketing_events
  SET tickets_sold = tickets_sold + 1,
      gross_revenue = gross_revenue + COALESCE(v_event.ticket_price, 0),
      deligo_commission = deligo_commission + v_commission,
      net_amount = net_amount + v_restaurant_amount
  WHERE id = p_event_id;

  UPDATE public.restaurant_event_wallets
  SET balance = balance + v_restaurant_amount,
      available_balance = available_balance + v_restaurant_amount,
      updated_at = now()
  WHERE event_id = p_event_id;

  RETURN v_ticket_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.validate_marketing_event_ticket(
  p_ticket_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket public.marketing_event_tickets%ROWTYPE;
  v_event public.marketing_events%ROWTYPE;
  v_owner_id UUID;
BEGIN
  SELECT *
  INTO v_ticket
  FROM public.marketing_event_tickets
  WHERE ticket_code = upper(trim(p_ticket_code))
     OR qr_code = trim(p_ticket_code)
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ticket_not_found');
  END IF;

  SELECT * INTO v_event FROM public.marketing_events WHERE id = v_ticket.event_id;
  SELECT owner_id INTO v_owner_id FROM public.restaurants WHERE id = v_event.restaurant_id;

  IF auth.uid() IS DISTINCT FROM v_owner_id
     AND NOT public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']) THEN
    RAISE EXCEPTION 'not_allowed_to_validate_ticket';
  END IF;

  IF v_ticket.status = 'used' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ticket_already_used',
      'used_at', v_ticket.used_at,
      'validated_by', v_ticket.validated_by
    );
  END IF;

  IF v_ticket.status <> 'sold' THEN
    RETURN jsonb_build_object('success', false, 'error', 'ticket_not_active');
  END IF;

  UPDATE public.marketing_event_tickets
  SET status = 'used',
      used_at = now(),
      validated_by = auth.uid(),
      validation_metadata = jsonb_build_object('source', 'restaurant_scanner')
  WHERE id = v_ticket.id;

  UPDATE public.marketing_events
  SET tickets_used = tickets_used + 1
  WHERE id = v_ticket.event_id;

  RETURN jsonb_build_object('success', true, 'event_id', v_ticket.event_id);
END;
$$;
CREATE OR REPLACE FUNCTION public.apply_marketing_coupon(
  p_code TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_campaign public.marketing_campaigns%ROWTYPE;
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT *
  INTO v_campaign
  FROM public.marketing_campaigns
  WHERE upper(coupon_code) = upper(trim(p_code))
    AND active IS TRUE
    AND starts_at <= now()
    AND (ends_at IS NULL OR ends_at >= now())
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'coupon_not_found');
  END IF;

  INSERT INTO public.marketing_coupon_redemptions (
    campaign_id,
    user_id,
    coupon_code,
    discount_type,
    discount_value
  )
  VALUES (
    v_campaign.id,
    v_user_id,
    upper(trim(p_code)),
    COALESCE(v_campaign.discount_type, 'fixed_amount'),
    v_campaign.discount_value
  )
  ON CONFLICT (campaign_id, user_id) DO UPDATE SET
    status = 'reserved',
    created_at = now()
  RETURNING campaign_id INTO v_campaign.id;

  UPDATE public.marketing_campaigns
  SET clicks = clicks + 1
  WHERE id = v_campaign.id;

  RETURN jsonb_build_object(
    'success', true,
    'campaign_id', v_campaign.id,
    'discount_type', v_campaign.discount_type,
    'discount_value', v_campaign.discount_value
  );
END;
$$;
ALTER TABLE public.marketing_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_request_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_request_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_event_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_event_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_event_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_event_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_coupon_redemptions ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION public.is_restaurant_owner(p_restaurant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.restaurants r
    WHERE r.id = p_restaurant_id
      AND r.owner_id = auth.uid()
  );
$$;
DROP POLICY IF EXISTS marketing_requests_staff_select ON public.marketing_requests;
CREATE POLICY marketing_requests_staff_select ON public.marketing_requests
  FOR SELECT TO authenticated
  USING (public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']));
DROP POLICY IF EXISTS marketing_requests_restaurant_select ON public.marketing_requests;
CREATE POLICY marketing_requests_restaurant_select ON public.marketing_requests
  FOR SELECT TO authenticated
  USING (public.is_restaurant_owner(restaurant_id));
DROP POLICY IF EXISTS marketing_requests_restaurant_insert ON public.marketing_requests;
CREATE POLICY marketing_requests_restaurant_insert ON public.marketing_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    requested_by = auth.uid()
    AND public.is_restaurant_owner(restaurant_id)
  );
DROP POLICY IF EXISTS marketing_requests_staff_update ON public.marketing_requests;
CREATE POLICY marketing_requests_staff_update ON public.marketing_requests
  FOR UPDATE TO authenticated
  USING (
    public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
    OR public.is_restaurant_owner(restaurant_id)
  )
  WITH CHECK (
    public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
    OR public.is_restaurant_owner(restaurant_id)
  );
DROP POLICY IF EXISTS marketing_related_staff_select ON public.marketing_request_history;
CREATE POLICY marketing_related_staff_select ON public.marketing_request_history
  FOR SELECT TO authenticated
  USING (
    public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
    OR EXISTS (
      SELECT 1 FROM public.marketing_requests mr
      WHERE mr.id = request_id AND public.is_restaurant_owner(mr.restaurant_id)
    )
  );
DROP POLICY IF EXISTS marketing_messages_select ON public.marketing_request_messages;
CREATE POLICY marketing_messages_select ON public.marketing_request_messages
  FOR SELECT TO authenticated
  USING (
    public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
    OR EXISTS (
      SELECT 1 FROM public.marketing_requests mr
      WHERE mr.id = request_id AND public.is_restaurant_owner(mr.restaurant_id)
    )
  );
DROP POLICY IF EXISTS marketing_messages_insert ON public.marketing_request_messages;
CREATE POLICY marketing_messages_insert ON public.marketing_request_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND (
      public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
      OR EXISTS (
        SELECT 1 FROM public.marketing_requests mr
        WHERE mr.id = request_id AND public.is_restaurant_owner(mr.restaurant_id)
      )
    )
  );
DROP POLICY IF EXISTS marketing_assets_select ON public.marketing_assets;
CREATE POLICY marketing_assets_select ON public.marketing_assets
  FOR SELECT TO authenticated
  USING (
    public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
    OR public.is_restaurant_owner(restaurant_id)
  );
DROP POLICY IF EXISTS marketing_assets_staff_insert ON public.marketing_assets;
CREATE POLICY marketing_assets_staff_insert ON public.marketing_assets
  FOR INSERT TO authenticated
  WITH CHECK (public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']));
DROP POLICY IF EXISTS marketing_events_public_select ON public.marketing_events;
CREATE POLICY marketing_events_public_select ON public.marketing_events
  FOR SELECT TO authenticated
  USING (
    status = 'published'
    OR public.is_restaurant_owner(restaurant_id)
    OR public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
  );
DROP POLICY IF EXISTS marketing_events_staff_update ON public.marketing_events;
CREATE POLICY marketing_events_staff_update ON public.marketing_events
  FOR UPDATE TO authenticated
  USING (
    public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
    OR public.is_restaurant_owner(restaurant_id)
  )
  WITH CHECK (
    public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
    OR public.is_restaurant_owner(restaurant_id)
  );
DROP POLICY IF EXISTS restaurant_event_wallets_select ON public.restaurant_event_wallets;
CREATE POLICY restaurant_event_wallets_select ON public.restaurant_event_wallets
  FOR SELECT TO authenticated
  USING (
    public.is_restaurant_owner(restaurant_id)
    OR public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
  );
DROP POLICY IF EXISTS marketing_tickets_owner_select ON public.marketing_event_tickets;
CREATE POLICY marketing_tickets_owner_select ON public.marketing_event_tickets
  FOR SELECT TO authenticated
  USING (
    buyer_id = auth.uid()
    OR EXISTS (
      SELECT 1
      FROM public.marketing_events me
      WHERE me.id = event_id
        AND (
          public.is_restaurant_owner(me.restaurant_id)
          OR public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
        )
    )
  );
DROP POLICY IF EXISTS marketing_metrics_select ON public.marketing_event_metrics;
CREATE POLICY marketing_metrics_select ON public.marketing_event_metrics
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.marketing_events me
      WHERE me.id = event_id
        AND (
          me.status = 'published'
          OR public.is_restaurant_owner(me.restaurant_id)
          OR public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
        )
    )
  );
DROP POLICY IF EXISTS marketing_reports_select ON public.marketing_event_reports;
CREATE POLICY marketing_reports_select ON public.marketing_event_reports
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.marketing_events me
      WHERE me.id = event_id
        AND (
          public.is_restaurant_owner(me.restaurant_id)
          OR public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
        )
    )
  );
DROP POLICY IF EXISTS marketing_campaigns_client_select ON public.marketing_campaigns;
CREATE POLICY marketing_campaigns_client_select ON public.marketing_campaigns
  FOR SELECT TO authenticated
  USING (
    active IS TRUE
    OR public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
    OR (restaurant_id IS NOT NULL AND public.is_restaurant_owner(restaurant_id))
  );
DROP POLICY IF EXISTS marketing_campaigns_staff_all ON public.marketing_campaigns;
CREATE POLICY marketing_campaigns_staff_all ON public.marketing_campaigns
  FOR ALL TO authenticated
  USING (public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']))
  WITH CHECK (public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']));
DROP POLICY IF EXISTS marketing_coupon_redemptions_owner_select ON public.marketing_coupon_redemptions;
CREATE POLICY marketing_coupon_redemptions_owner_select ON public.marketing_coupon_redemptions
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent'])
  );
GRANT SELECT, INSERT, UPDATE ON public.marketing_requests TO authenticated;
GRANT SELECT ON public.marketing_request_history TO authenticated;
GRANT SELECT, INSERT ON public.marketing_request_messages TO authenticated;
GRANT SELECT, INSERT ON public.marketing_assets TO authenticated;
GRANT SELECT, UPDATE ON public.marketing_events TO authenticated;
GRANT SELECT ON public.restaurant_event_wallets TO authenticated;
GRANT SELECT ON public.marketing_event_tickets TO authenticated;
GRANT SELECT ON public.marketing_event_metrics TO authenticated;
GRANT SELECT ON public.marketing_event_reports TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.marketing_campaigns TO authenticated;
GRANT SELECT ON public.marketing_coupon_redemptions TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_marketing_request_and_publish(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sell_marketing_event_ticket(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_marketing_event_ticket(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_marketing_coupon(TEXT) TO authenticated;
GRANT ALL ON public.marketing_requests TO service_role;
GRANT ALL ON public.marketing_request_history TO service_role;
GRANT ALL ON public.marketing_request_messages TO service_role;
GRANT ALL ON public.marketing_assets TO service_role;
GRANT ALL ON public.marketing_events TO service_role;
GRANT ALL ON public.restaurant_event_wallets TO service_role;
GRANT ALL ON public.marketing_event_tickets TO service_role;
GRANT ALL ON public.marketing_event_metrics TO service_role;
GRANT ALL ON public.marketing_event_reports TO service_role;
GRANT ALL ON public.marketing_campaigns TO service_role;
GRANT ALL ON public.marketing_coupon_redemptions TO service_role;
