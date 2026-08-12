BEGIN;
CREATE TABLE IF NOT EXISTS public.alerts_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NULL,
  order_id UUID NULL,
  alert_type TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'info',
  message TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.cron_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'completed',
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  ran_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.gamification_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  role TEXT NOT NULL,
  mission_key TEXT NOT NULL,
  points INTEGER NOT NULL DEFAULT 0,
  reward_type TEXT NULL,
  reward_value NUMERIC NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.leaderboards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  board_type TEXT NOT NULL,
  subject_id UUID NOT NULL,
  label TEXT NOT NULL,
  score NUMERIC NOT NULL DEFAULT 0,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.zone_order_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  zone_key TEXT NOT NULL UNIQUE,
  city TEXT NULL,
  total_orders INTEGER NOT NULL DEFAULT 0,
  active_orders INTEGER NOT NULL DEFAULT 0,
  completed_orders INTEGER NOT NULL DEFAULT 0,
  cancelled_orders INTEGER NOT NULL DEFAULT 0,
  avg_delivery_fee NUMERIC NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS public.courier_stats (
  courier_id UUID PRIMARY KEY,
  rating NUMERIC NOT NULL DEFAULT 0,
  total_deliveries INTEGER NOT NULL DEFAULT 0,
  earnings_today NUMERIC NOT NULL DEFAULT 0,
  acceptance_rate NUMERIC NOT NULL DEFAULT 0,
  cancellation_rate NUMERIC NOT NULL DEFAULT 0,
  balance NUMERIC NOT NULL DEFAULT 0,
  target_daily_mzn NUMERIC NOT NULL DEFAULT 2000,
  progress_pct NUMERIC NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE OR REPLACE FUNCTION public.seed_deligo_operational_order(
  p_payment_ref TEXT,
  p_client_id UUID,
  p_restaurant_id UUID,
  p_courier_id UUID,
  p_status TEXT,
  p_total_amount NUMERIC,
  p_delivery_fee NUMERIC,
  p_created_at TIMESTAMPTZ,
  p_delivery_address TEXT,
  p_delivery_latitude NUMERIC DEFAULT NULL,
  p_delivery_longitude NUMERIC DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_order_id UUID;
  v_menu_item_id UUID;
  v_food_total NUMERIC;
  v_platform_fee NUMERIC;
  v_restaurant_amount NUMERIC;
  v_courier_amount NUMERIC;
BEGIN
  SELECT order_id
  INTO v_order_id
  FROM public.payments
  WHERE payment_ref = p_payment_ref
  LIMIT 1;

  IF v_order_id IS NOT NULL THEN
    RETURN v_order_id;
  END IF;

  SELECT id
  INTO v_menu_item_id
  FROM public.menu_items
  WHERE restaurant_id = p_restaurant_id
  ORDER BY is_available DESC, created_at ASC NULLS LAST, name ASC
  LIMIT 1;

  v_order_id := gen_random_uuid();
  v_food_total := GREATEST(COALESCE(p_total_amount, 0) - COALESCE(p_delivery_fee, 0), 0);
  v_platform_fee := ROUND((v_food_total * 0.15) + (COALESCE(p_delivery_fee, 0) * 0.15), 2);
  v_restaurant_amount := ROUND(v_food_total * 0.85, 2);
  v_courier_amount := ROUND(COALESCE(p_delivery_fee, 0) * 0.85, 2);

  INSERT INTO public.orders (
    id,
    client_id,
    customer_id,
    restaurant_id,
    courier_id,
    status,
    total_amount,
    total,
    payment_status,
    delivery_fee,
    admin_commission,
    delivery_address,
    delivery_latitude,
    delivery_longitude,
    created_at,
    updated_at,
    confirmed_by_customer
  ) VALUES (
    v_order_id,
    p_client_id,
    p_client_id,
    p_restaurant_id,
    p_courier_id,
    p_status,
    p_total_amount,
    p_total_amount,
    CASE
      WHEN p_status IN ('cancelled', 'pending') THEN 'pending'
      ELSE 'completed'
    END,
    LEAST(200, GREATEST(100, COALESCE(p_delivery_fee, 100))),
    v_platform_fee,
    p_delivery_address,
    p_delivery_latitude,
    p_delivery_longitude,
    p_created_at,
    p_created_at + INTERVAL '22 minutes',
    CASE WHEN p_status IN ('delivered', 'completed') THEN TRUE ELSE FALSE END
  );

  IF v_menu_item_id IS NOT NULL THEN
    INSERT INTO public.order_items (
      id,
      order_id,
      menu_item_id,
      quantity,
      price,
      unit_price,
      subtotal,
      created_at
    ) VALUES (
      gen_random_uuid(),
      v_order_id,
      v_menu_item_id,
      1,
      v_food_total,
      v_food_total,
      v_food_total,
      p_created_at
    );
  END IF;

  INSERT INTO public.payments (
    id,
    order_id,
    amount,
    payment_method,
    provider,
    payment_ref,
    transaction_id,
    status,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_order_id,
    p_total_amount,
    CASE WHEN COALESCE(p_delivery_fee, 0) > 0 THEN 'mobile_money' ELSE 'cash' END,
    'seed',
    p_payment_ref,
    p_payment_ref,
    CASE
      WHEN p_status = 'cancelled' THEN 'failed'
      WHEN p_status = 'pending' THEN 'pending'
      ELSE 'completed'
    END,
    p_created_at,
    p_created_at
  );

  INSERT INTO public.payment_splits (
    id,
    order_id,
    total_amount,
    platform_fee,
    restaurant_amount,
    courier_amount,
    status,
    created_at
  )
  SELECT
    gen_random_uuid(),
    v_order_id,
    p_total_amount,
    v_platform_fee,
    v_restaurant_amount,
    v_courier_amount,
    CASE
      WHEN p_status IN ('accepted', 'preparing', 'ready', 'in_transit', 'delivered', 'completed') THEN 'completed'
      ELSE 'pending'
    END,
    p_created_at
  WHERE NOT EXISTS (
    SELECT 1 FROM public.payment_splits WHERE order_id = v_order_id
  );

  IF p_courier_id IS NOT NULL THEN
    INSERT INTO public.deliveries (
      id,
      order_id,
      courier_id,
      pickup_latitude,
      pickup_longitude,
      delivery_latitude,
      delivery_longitude,
      current_latitude,
      current_longitude,
      status,
      created_at,
      updated_at
    )
    SELECT
      gen_random_uuid(),
      v_order_id,
      p_courier_id,
      r.latitude,
      r.longitude,
      p_delivery_latitude,
      p_delivery_longitude,
      COALESCE((r.latitude + p_delivery_latitude) / 2, r.latitude),
      COALESCE((r.longitude + p_delivery_longitude) / 2, r.longitude),
      CASE
        WHEN p_status IN ('in_transit', 'arrived') THEN 'in_transit'
        WHEN p_status IN ('delivered', 'completed') THEN 'delivered'
        ELSE 'pending'
      END,
      p_created_at,
      p_created_at
    FROM public.restaurants r
    WHERE r.id = p_restaurant_id
      AND NOT EXISTS (
        SELECT 1 FROM public.deliveries d WHERE d.order_id = v_order_id
      );
  END IF;

  RETURN v_order_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.refresh_deligo_operational_metrics()
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_client_id UUID;
  v_restaurant_owner_id UUID;
  v_courier_id UUID;
  v_restaurant_id UUID;
  v_wallet_balance NUMERIC := 0;
  v_today_earnings NUMERIC := 0;
  v_total_deliveries INTEGER := 0;
  v_cancelled_count INTEGER := 0;
  v_assigned_count INTEGER := 0;
  v_rating NUMERIC := 4.8;
  v_has_courier_stats_shape BOOLEAN := FALSE;
  v_has_zone_stats_shape BOOLEAN := FALSE;
  v_has_alerts_shape BOOLEAN := FALSE;
  v_has_gamification_shape BOOLEAN := FALSE;
  v_has_leaderboards_shape BOOLEAN := FALSE;
  v_has_cron_runs_shape BOOLEAN := FALSE;
  v_cron_has_scheduled_at BOOLEAN := FALSE;
BEGIN
  SELECT id INTO v_client_id FROM auth.users WHERE email = 'anwarismael258@gmail.com' LIMIT 1;
  SELECT id INTO v_restaurant_owner_id FROM auth.users WHERE email = 'anis.justwork@gmail.com' LIMIT 1;
  SELECT id INTO v_courier_id FROM auth.users WHERE email = 'youngmonster199@gmail.com' LIMIT 1;

  SELECT id INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_restaurant_owner_id
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1;

  IF v_client_id IS NULL OR v_restaurant_id IS NULL OR v_courier_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(balance, 0)
  INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = v_courier_id
  LIMIT 1;

  SELECT COALESCE(SUM(ps.courier_amount), 0), COUNT(*)
  INTO v_today_earnings, v_total_deliveries
  FROM public.payment_splits ps
  JOIN public.orders o ON o.id = ps.order_id
  WHERE o.courier_id = v_courier_id
    AND o.status IN ('delivered', 'completed')
    AND o.created_at >= date_trunc('day', NOW());

  SELECT COUNT(*)
  INTO v_cancelled_count
  FROM public.orders
  WHERE courier_id = v_courier_id
    AND status = 'cancelled';

  SELECT COUNT(*)
  INTO v_assigned_count
  FROM public.orders
  WHERE courier_id = v_courier_id;

  SELECT COALESCE(AVG(rating), 4.8)
  INTO v_rating
  FROM public.reviews rv
  JOIN public.orders o ON o.id = rv.order_id
  WHERE o.courier_id = v_courier_id;

  SELECT COUNT(*) = 9 INTO v_has_courier_stats_shape
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'courier_stats'
    AND column_name IN ('courier_id', 'rating', 'total_deliveries', 'earnings_today', 'acceptance_rate', 'cancellation_rate', 'balance', 'target_daily_mzn', 'progress_pct');

  IF v_has_courier_stats_shape THEN
    INSERT INTO public.courier_stats (
      courier_id,
      rating,
      total_deliveries,
      earnings_today,
      acceptance_rate,
      cancellation_rate,
      balance,
      target_daily_mzn,
      progress_pct,
      updated_at
    ) VALUES (
      v_courier_id,
      ROUND(COALESCE(v_rating, 4.8), 1),
      COALESCE(v_total_deliveries, 0),
      COALESCE(v_today_earnings, 0),
      CASE WHEN v_assigned_count = 0 THEN 92 ELSE ROUND(((v_assigned_count - v_cancelled_count)::NUMERIC / v_assigned_count::NUMERIC) * 100, 2) END,
      CASE WHEN v_assigned_count = 0 THEN 3 ELSE ROUND((v_cancelled_count::NUMERIC / v_assigned_count::NUMERIC) * 100, 2) END,
      COALESCE(v_wallet_balance, 0),
      2000,
      LEAST(100, ROUND((COALESCE(v_today_earnings, 0) / 2000) * 100, 2)),
      NOW()
    )
    ON CONFLICT (courier_id) DO UPDATE SET
      rating = EXCLUDED.rating,
      total_deliveries = EXCLUDED.total_deliveries,
      earnings_today = EXCLUDED.earnings_today,
      acceptance_rate = EXCLUDED.acceptance_rate,
      cancellation_rate = EXCLUDED.cancellation_rate,
      balance = EXCLUDED.balance,
      target_daily_mzn = EXCLUDED.target_daily_mzn,
      progress_pct = EXCLUDED.progress_pct,
      updated_at = NOW();
  END IF;

  SELECT COUNT(*) = 8 INTO v_has_zone_stats_shape
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'zone_order_stats'
    AND column_name IN ('zone_key', 'city', 'total_orders', 'active_orders', 'completed_orders', 'cancelled_orders', 'avg_delivery_fee', 'updated_at');

  IF v_has_zone_stats_shape THEN
    INSERT INTO public.zone_order_stats (
      id,
      zone_key,
      city,
      total_orders,
      active_orders,
      completed_orders,
      cancelled_orders,
      avg_delivery_fee,
      updated_at
    )
    SELECT
      COALESCE(z.id, gen_random_uuid()),
      src.zone_key,
      src.city,
      src.total_orders,
      src.active_orders,
      src.completed_orders,
      src.cancelled_orders,
      src.avg_delivery_fee,
      NOW()
    FROM (
      SELECT
        LOWER(COALESCE(NULLIF(TRIM(o.delivery_address), ''), 'maputo')) AS zone_key,
        'Maputo'::TEXT AS city,
        COUNT(*)::INTEGER AS total_orders,
        COUNT(*) FILTER (WHERE o.status IN ('pending', 'accepted', 'preparing', 'ready', 'in_transit'))::INTEGER AS active_orders,
        COUNT(*) FILTER (WHERE o.status IN ('delivered', 'completed'))::INTEGER AS completed_orders,
        COUNT(*) FILTER (WHERE o.status = 'cancelled')::INTEGER AS cancelled_orders,
        ROUND(COALESCE(AVG(COALESCE(o.delivery_fee, 0)), 0), 2) AS avg_delivery_fee
      FROM public.orders o
      WHERE o.restaurant_id = v_restaurant_id
      GROUP BY 1
    ) src
    LEFT JOIN public.zone_order_stats z ON z.zone_key = src.zone_key
    ON CONFLICT (zone_key) DO UPDATE SET
      city = EXCLUDED.city,
      total_orders = EXCLUDED.total_orders,
      active_orders = EXCLUDED.active_orders,
      completed_orders = EXCLUDED.completed_orders,
      cancelled_orders = EXCLUDED.cancelled_orders,
      avg_delivery_fee = EXCLUDED.avg_delivery_fee,
      updated_at = NOW();
  END IF;

  SELECT COUNT(*) = 6 INTO v_has_alerts_shape
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'alerts_log'
    AND column_name IN ('restaurant_id', 'order_id', 'alert_type', 'severity', 'message', 'metadata');

  IF v_has_alerts_shape THEN
    DELETE FROM public.alerts_log
    WHERE metadata ->> 'source' = 'production_seed'
      AND COALESCE(restaurant_id, v_restaurant_id) = v_restaurant_id;

    INSERT INTO public.alerts_log (restaurant_id, order_id, alert_type, severity, message, metadata, created_at)
    SELECT
      v_restaurant_id,
      o.id,
      'order_delayed',
      'high',
      'Pedido atrasado há mais de 60 minutos e precisa de atenção.',
      jsonb_build_object('source', 'production_seed', 'status', o.status, 'minutes_open', ROUND(EXTRACT(EPOCH FROM (NOW() - o.created_at)) / 60)),
      NOW()
    FROM public.orders o
    WHERE o.restaurant_id = v_restaurant_id
      AND o.status IN ('accepted', 'preparing', 'ready')
      AND o.created_at <= NOW() - INTERVAL '60 minutes';

    INSERT INTO public.alerts_log (restaurant_id, order_id, alert_type, severity, message, metadata, created_at)
    SELECT
      v_restaurant_id,
      NULL,
      'low_stock',
      'medium',
      'Produto indisponível no cardápio e precisa de reposição.',
      jsonb_build_object('source', 'production_seed', 'menu_item_id', mi.id, 'name', mi.name),
      NOW()
    FROM public.menu_items mi
    WHERE mi.restaurant_id = v_restaurant_id
      AND COALESCE(mi.is_available, true) = false;

    INSERT INTO public.alerts_log (restaurant_id, order_id, alert_type, severity, message, metadata, created_at)
    SELECT
      v_restaurant_id,
      rv.order_id,
      'negative_review',
      'medium',
      'Avaliação negativa recebida. Responda o cliente o quanto antes.',
      jsonb_build_object('source', 'production_seed', 'rating', rv.rating, 'comment', rv.comment),
      NOW()
    FROM public.reviews rv
    JOIN public.orders o ON o.id = rv.order_id
    WHERE o.restaurant_id = v_restaurant_id
      AND rv.rating <= 3;
  END IF;

  SELECT COUNT(*) = 7 INTO v_has_gamification_shape
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'gamification_logs'
    AND column_name IN ('user_id', 'role', 'mission_key', 'points', 'reward_type', 'reward_value', 'metadata');

  IF v_has_gamification_shape THEN
    DELETE FROM public.gamification_logs
    WHERE metadata ->> 'source' = 'production_seed'
      AND user_id IN (v_client_id, v_restaurant_owner_id, v_courier_id);

    INSERT INTO public.gamification_logs (user_id, role, mission_key, points, reward_type, reward_value, metadata, created_at)
    VALUES
      (v_client_id, 'customer', '3_pedidos_desconto', 120, 'coupon', 100, jsonb_build_object('source', 'production_seed', 'progress', '3/3')),
      (v_client_id, 'customer', '5_avaliacoes_cupom', 80, 'coupon', 50, jsonb_build_object('source', 'production_seed', 'progress', '4/5')),
      (v_restaurant_owner_id, 'restaurant', 'resposta_rapida_destaque', 140, 'visibility', 1, jsonb_build_object('source', 'production_seed', 'progress', 'ativo')),
      (v_courier_id, 'courier', '10_entregas_bonus', 200, 'bonus', 150, jsonb_build_object('source', 'production_seed', 'progress', '6/10')),
      (v_courier_id, 'courier', '5_estrelas_prioridade', 90, 'priority', 1, jsonb_build_object('source', 'production_seed', 'progress', '4/5'));
  END IF;

  SELECT COUNT(*) = 5 INTO v_has_leaderboards_shape
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'leaderboards'
    AND column_name IN ('board_type', 'subject_id', 'label', 'score', 'metadata');

  IF v_has_leaderboards_shape THEN
    DELETE FROM public.leaderboards
    WHERE metadata ->> 'source' = 'production_seed';

    INSERT INTO public.leaderboards (board_type, subject_id, label, score, metadata, created_at)
    VALUES
      ('restaurants', v_restaurant_id, 'Deligo Restaurante', 4.6, jsonb_build_object('source', 'production_seed', 'metric', 'rating')),
      ('couriers', v_courier_id, 'Deligo Biker', 4.8, jsonb_build_object('source', 'production_seed', 'metric', 'rating')),
      ('customers', v_client_id, 'Anwar Ismael', 96, jsonb_build_object('source', 'production_seed', 'metric', 'reputation'));
  END IF;

  SELECT COUNT(*) = 4 INTO v_has_cron_runs_shape
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'cron_runs'
    AND column_name IN ('job_name', 'status', 'details', 'ran_at');

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'cron_runs'
      AND column_name = 'scheduled_at'
  ) INTO v_cron_has_scheduled_at;

  IF v_has_cron_runs_shape THEN
    IF v_cron_has_scheduled_at THEN
      INSERT INTO public.cron_runs (job_name, scheduled_at, status, details, ran_at)
      VALUES (
        'refresh_deligo_operational_metrics',
        NOW(),
        'completed',
        jsonb_build_object('source', 'production_seed', 'restaurant_id', v_restaurant_id, 'courier_id', v_courier_id),
        NOW()
      );
    ELSE
      INSERT INTO public.cron_runs (job_name, status, details, ran_at)
      VALUES (
        'refresh_deligo_operational_metrics',
        'completed',
        jsonb_build_object('source', 'production_seed', 'restaurant_id', v_restaurant_id, 'courier_id', v_courier_id),
        NOW()
      );
    END IF;
  END IF;
END;
$$;
DO $$
DECLARE
  v_client_id UUID;
  v_restaurant_owner_id UUID;
  v_courier_id UUID;
  v_restaurant_id UUID;
BEGIN
  SELECT id INTO v_client_id FROM auth.users WHERE email = 'anwarismael258@gmail.com' LIMIT 1;
  SELECT id INTO v_restaurant_owner_id FROM auth.users WHERE email = 'anis.justwork@gmail.com' LIMIT 1;
  SELECT id INTO v_courier_id FROM auth.users WHERE email = 'youngmonster199@gmail.com' LIMIT 1;

  SELECT id INTO v_restaurant_id
  FROM public.restaurants
  WHERE owner_id = v_restaurant_owner_id
  ORDER BY created_at ASC NULLS LAST
  LIMIT 1;

  IF v_client_id IS NULL OR v_restaurant_id IS NULL OR v_courier_id IS NULL THEN
    RAISE NOTICE 'Production-grade ops seed skipped: base users/restaurant not found.';
    RETURN;
  END IF;

  PERFORM public.seed_deligo_operational_order(
    'seed-ops-simultaneous-1',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'accepted',
    1150,
    100,
    NOW() - INTERVAL '28 minutes',
    'Polana Cimento A',
    -25.9622,
    32.5881
  );

  PERFORM public.seed_deligo_operational_order(
    'seed-ops-simultaneous-2',
    v_client_id,
    v_restaurant_id,
    NULL,
    'preparing',
    1420,
    150,
    NOW() - INTERVAL '18 minutes',
    'Sommerschield',
    -25.9501,
    32.6031
  );

  PERFORM public.seed_deligo_operational_order(
    'seed-ops-simultaneous-3',
    v_client_id,
    v_restaurant_id,
    v_courier_id,
    'in_transit',
    1680,
    200,
    NOW() - INTERVAL '12 minutes',
    'Triunfo',
    -25.9442,
    32.6128
  );

  PERFORM public.seed_deligo_operational_order(
    'seed-ops-cancelled-random-1',
    v_client_id,
    v_restaurant_id,
    NULL,
    'cancelled',
    990,
    0,
    NOW() - INTERVAL '3 hours 12 minutes',
    'Retirar no restaurante',
    NULL,
    NULL
  );

  PERFORM public.seed_deligo_operational_order(
    'seed-ops-cancelled-random-2',
    v_client_id,
    v_restaurant_id,
    NULL,
    'cancelled',
    870,
    0,
    NOW() - INTERVAL '6 hours 25 minutes',
    'Retirar no restaurante',
    NULL,
    NULL
  );

  PERFORM public.refresh_deligo_operational_metrics();
END $$;
DROP FUNCTION IF EXISTS public.seed_deligo_operational_order(TEXT, UUID, UUID, UUID, TEXT, NUMERIC, NUMERIC, TIMESTAMPTZ, TEXT, NUMERIC, NUMERIC);
COMMIT;
