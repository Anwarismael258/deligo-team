BEGIN;
CREATE OR REPLACE FUNCTION public.create_rate_limited_app_notification(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_action text DEFAULT NULL,
  p_entity_id text DEFAULT NULL,
  p_priority text DEFAULT 'NORMAL',
  p_channel text DEFAULT 'system',
  p_metadata jsonb DEFAULT '{}'::jsonb,
  p_cooldown_minutes integer DEFAULT 60,
  p_dedupe_key text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_exists boolean := false;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.push_notifications
    WHERE user_id = p_user_id
      AND type = p_type
      AND (
        (p_entity_id IS NOT NULL AND entity_id = p_entity_id)
        OR (p_dedupe_key IS NOT NULL AND metadata->>'dedupe_key' = p_dedupe_key)
        OR (p_entity_id IS NULL AND p_dedupe_key IS NULL)
      )
      AND created_at > now() - make_interval(mins => GREATEST(COALESCE(p_cooldown_minutes, 60), 1))
  )
  INTO v_exists;

  IF v_exists THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.push_notifications (
    user_id,
    type,
    title,
    body,
    action,
    entity_id,
    priority,
    channel,
    data,
    metadata,
    created_at
  )
  VALUES (
    p_user_id,
    p_type,
    p_title,
    p_body,
    p_action,
    p_entity_id,
    p_priority,
    p_channel,
    CASE
      WHEN p_dedupe_key IS NULL THEN p_metadata
      ELSE COALESCE(p_metadata, '{}'::jsonb) || jsonb_build_object('dedupe_key', p_dedupe_key)
    END,
    CASE
      WHEN p_dedupe_key IS NULL THEN p_metadata
      ELSE COALESCE(p_metadata, '{}'::jsonb) || jsonb_build_object('dedupe_key', p_dedupe_key)
    END,
    now()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.trg_notify_refund_started()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
BEGIN
  v_status := COALESCE(NEW.status, '');
  IF v_status <> 'pending' OR COALESCE(NEW.refund_amount, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  PERFORM public.create_rate_limited_app_notification(
    p_user_id := NEW.user_id,
    p_type := 'REFUND_STARTED',
    p_title := 'Reembolso iniciado ⏳',
    p_body := 'O seu reembolso foi iniciado e sera creditado assim que for confirmado.',
    p_action := 'OPEN_WALLET',
    p_entity_id := NEW.order_id::text,
    p_priority := 'HIGH',
    p_channel := 'wallet',
    p_metadata := jsonb_build_object(
      'order_id', NEW.order_id,
      'refund_id', NEW.id,
      'refund_amount', NEW.refund_amount,
      'refund_percent', NEW.refund_percent
    ),
    p_cooldown_minutes := 180,
    p_dedupe_key := 'refund-started-' || NEW.id::text
  );

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_refund_started ON public.refunds;
CREATE TRIGGER trg_notify_refund_started
AFTER INSERT OR UPDATE ON public.refunds
FOR EACH ROW
EXECUTE FUNCTION public.trg_notify_refund_started();
CREATE OR REPLACE FUNCTION public.dispatch_engagement_notifications()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sent_promo integer := 0;
  v_sent_free_delivery integer := 0;
  v_sent_retention integer := 0;
  v_created uuid;
  v_user record;
BEGIN
  FOR v_user IN
    SELECT
      p.id AS user_id,
      p.full_name,
      MAX(o.created_at) FILTER (WHERE COALESCE(o.client_id, o.customer_id) = p.id) AS last_order_at,
      COUNT(*) FILTER (
        WHERE COALESCE(o.client_id, o.customer_id) = p.id
          AND o.status IN ('delivered', 'completed')
      ) AS completed_orders
    FROM public.profiles p
    LEFT JOIN public.orders o
      ON COALESCE(o.client_id, o.customer_id) = p.id
    WHERE COALESCE(p.role, 'client') = 'client'
      AND COALESCE(p.is_blocked, false) = false
    GROUP BY p.id, p.full_name
  LOOP
    IF v_user.completed_orders >= 1 AND (
      v_user.last_order_at IS NULL
      OR v_user.last_order_at < now() - interval '3 days'
    ) THEN
      SELECT public.create_rate_limited_app_notification(
        p_user_id := v_user.user_id,
        p_type := 'FREE_DELIVERY_PROMO',
        p_title := 'Frete minimo a partir de 100 MZN 🚚',
        p_body := 'Peça hoje e aproveite entregas com taxa minima padronizada em todo o app.',
        p_action := 'OPEN_EXPLORE',
        p_priority := 'MEDIUM',
        p_channel := 'marketing',
        p_metadata := jsonb_build_object('campaign', 'minimum_delivery_reminder'),
        p_cooldown_minutes := 72 * 60,
        p_dedupe_key := 'free-delivery-minimum'
      ) INTO v_created;
      IF v_created IS NOT NULL THEN
        v_sent_free_delivery := v_sent_free_delivery + 1;
      END IF;
    END IF;

    IF v_user.completed_orders >= 3 THEN
      SELECT public.create_rate_limited_app_notification(
        p_user_id := v_user.user_id,
        p_type := 'PROMO_OFFER',
        p_title := 'Tem ofertas novas para si 🎉',
        p_body := 'Descubra restaurantes em destaque, combos e novidades selecionadas para si.',
        p_action := 'OPEN_EXPLORE',
        p_priority := 'MEDIUM',
        p_channel := 'marketing',
        p_metadata := jsonb_build_object('campaign', 'featured_restaurants_offer'),
        p_cooldown_minutes := 7 * 24 * 60,
        p_dedupe_key := 'weekly-promo-offer'
      ) INTO v_created;
      IF v_created IS NOT NULL THEN
        v_sent_promo := v_sent_promo + 1;
      END IF;
    END IF;

    IF v_user.last_order_at IS NULL
       OR v_user.last_order_at < now() - interval '7 days' THEN
      SELECT public.create_rate_limited_app_notification(
        p_user_id := v_user.user_id,
        p_type := 'RETENTION_REMINDER',
        p_title := 'Estamos com saudades 🍽️',
        p_body := 'Volte ao app e explore restaurantes, favoritos e novos pratos perto de si.',
        p_action := 'OPEN_HOME',
        p_priority := 'LOW',
        p_channel := 'retention',
        p_metadata := jsonb_build_object('campaign', '7_day_retention'),
        p_cooldown_minutes := 7 * 24 * 60,
        p_dedupe_key := 'retention-7d'
      ) INTO v_created;
      IF v_created IS NOT NULL THEN
        v_sent_retention := v_sent_retention + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'promo_sent', v_sent_promo,
    'free_delivery_sent', v_sent_free_delivery,
    'retention_sent', v_sent_retention
  );
END;
$$;
COMMIT;
