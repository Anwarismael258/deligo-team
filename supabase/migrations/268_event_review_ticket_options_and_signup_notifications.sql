BEGIN;
ALTER TABLE public.marketing_requests
  ADD COLUMN IF NOT EXISTS event_category TEXT,
  ADD COLUMN IF NOT EXISTS event_type_detail TEXT,
  ADD COLUMN IF NOT EXISTS event_end_time TIME,
  ADD COLUMN IF NOT EXISTS max_capacity INTEGER,
  ADD COLUMN IF NOT EXISTS ticket_options JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS rules TEXT,
  ADD COLUMN IF NOT EXISTS refund_policy TEXT;
ALTER TABLE public.marketing_events
  ADD COLUMN IF NOT EXISTS event_category TEXT,
  ADD COLUMN IF NOT EXISTS event_type_detail TEXT,
  ADD COLUMN IF NOT EXISTS event_end_time TIME,
  ADD COLUMN IF NOT EXISTS max_capacity INTEGER,
  ADD COLUMN IF NOT EXISTS ticket_options JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS rules TEXT,
  ADD COLUMN IF NOT EXISTS refund_policy TEXT;
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
BEGIN
  SELECT *
  INTO v_request
  FROM public.marketing_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'marketing_request_not_found';
  END IF;

  IF NOT public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']) THEN
    RAISE EXCEPTION 'not_allowed_to_publish_marketing_request';
  END IF;

  INSERT INTO public.marketing_events (
    request_id,
    restaurant_id,
    title,
    description,
    event_type,
    event_category,
    event_type_detail,
    event_date,
    event_time,
    event_end_time,
    location,
    max_capacity,
    poster_url,
    banner_url,
    sells_tickets,
    ticket_price,
    ticket_quantity,
    ticket_options,
    rules,
    refund_policy,
    status,
    published_at
  )
  VALUES (
    v_request.id,
    v_request.restaurant_id,
    COALESCE(NULLIF(trim(v_request.campaign_title), ''), v_request.event_name),
    COALESCE(NULLIF(trim(v_request.campaign_description), ''), v_request.description),
    v_request.request_type,
    v_request.event_category,
    v_request.event_type_detail,
    v_request.event_date,
    v_request.event_time,
    v_request.event_end_time,
    v_request.location,
    v_request.max_capacity,
    COALESCE(NULLIF(trim(v_request.poster_url), ''), NULLIF(trim(v_request.banner_url), '')),
    v_request.banner_url,
    v_request.sells_tickets,
    v_request.ticket_price,
    v_request.ticket_quantity,
    COALESCE(v_request.ticket_options, '[]'::jsonb),
    v_request.rules,
    v_request.refund_policy,
    'published',
    now()
  )
  ON CONFLICT (request_id) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    event_type = EXCLUDED.event_type,
    event_category = EXCLUDED.event_category,
    event_type_detail = EXCLUDED.event_type_detail,
    event_date = EXCLUDED.event_date,
    event_time = EXCLUDED.event_time,
    event_end_time = EXCLUDED.event_end_time,
    location = EXCLUDED.location,
    max_capacity = EXCLUDED.max_capacity,
    poster_url = EXCLUDED.poster_url,
    banner_url = EXCLUDED.banner_url,
    sells_tickets = EXCLUDED.sells_tickets,
    ticket_price = EXCLUDED.ticket_price,
    ticket_quantity = EXCLUDED.ticket_quantity,
    ticket_options = EXCLUDED.ticket_options,
    rules = EXCLUDED.rules,
    refund_policy = EXCLUDED.refund_policy,
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
      published_at = COALESCE(published_at, now()),
      updated_at = now()
  WHERE id = p_request_id;

  INSERT INTO public.marketing_request_messages (
    request_id, sender_id, sender_role, body
  )
  VALUES (
    p_request_id,
    auth.uid(),
    'marketing_agent',
    'O evento foi aprovado pelo Marketing e publicado automaticamente na DeliGo.'
  );

  RETURN v_event_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.notify_admins_new_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile public.profiles%ROWTYPE;
  v_admin RECORD;
  v_title TEXT;
  v_body TEXT;
  v_role TEXT;
BEGIN
  SELECT *
  INTO v_profile
  FROM public.profiles
  WHERE id = NEW.id;

  v_role := lower(COALESCE(v_profile.role, NEW.raw_user_meta_data->>'role', 'client'));

  IF v_role = 'restaurant' THEN
    v_title := 'Novo restaurante registado';
    v_body := concat(
      'Nome: ', COALESCE(v_profile.full_name, NEW.raw_user_meta_data->>'full_name', 'Restaurante'),
      ' | Telefone: ', COALESCE(v_profile.phone, NEW.phone, NEW.raw_user_meta_data->>'phone', '-'),
      ' | Cidade: ', COALESCE(v_profile.city, NEW.raw_user_meta_data->>'city', '-')
    );
  ELSIF v_role IN ('courier', 'driver', 'delivery') THEN
    v_title := 'Novo entregador registado';
    v_body := concat(
      'Nome: ', COALESCE(v_profile.full_name, NEW.raw_user_meta_data->>'full_name', 'Entregador'),
      ' | Telefone: ', COALESCE(v_profile.phone, NEW.phone, NEW.raw_user_meta_data->>'phone', '-'),
      ' | Veiculo: ', COALESCE(NEW.raw_user_meta_data->>'vehicle', '-'),
      ' | Cidade: ', COALESCE(v_profile.city, NEW.raw_user_meta_data->>'city', '-')
    );
  ELSE
    v_title := 'Novo utilizador registado no DeliGo';
    v_body := concat(
      'Nome: ', COALESCE(v_profile.full_name, NEW.raw_user_meta_data->>'full_name', 'Novo utilizador'),
      ' | Telefone: ', COALESCE(v_profile.phone, NEW.phone, NEW.raw_user_meta_data->>'phone', '-'),
      ' | Email: ', COALESCE(NEW.email, v_profile.email, '-'),
      ' | Perfil: ', COALESCE(v_profile.role, NEW.raw_user_meta_data->>'role', 'client')
    );
  END IF;

  FOR v_admin IN
    SELECT id
    FROM public.profiles
    WHERE lower(COALESCE(role, '')) = 'admin'
  LOOP
    PERFORM public.create_app_notification(
      p_user_id := v_admin.id,
      p_type := 'USER_REGISTERED',
      p_title := v_title,
      p_body := v_body,
      p_action := 'OPEN_ADMIN_USERS',
      p_entity_id := NEW.id::text,
      p_priority := 'NORMAL',
      p_channel := 'admin',
      p_metadata := jsonb_build_object(
        'user_id', NEW.id,
        'role', v_role,
        'email', NEW.email,
        'phone', COALESCE(v_profile.phone, NEW.phone, NEW.raw_user_meta_data->>'phone'),
        'registered_at', now(),
        'server_dispatch_required', true,
        'source', 'auth_signup_trigger'
      ),
      p_dispatch_key := 'user_registered:' || NEW.id::text || ':' || v_admin.id::text
    );
  END LOOP;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_admins_new_signup ON auth.users;
CREATE TRIGGER trg_notify_admins_new_signup
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.notify_admins_new_signup();
COMMIT;
