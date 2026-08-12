BEGIN;
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron unavailable, skipping scheduler install: %', SQLERRM;
END;
$$;
CREATE OR REPLACE FUNCTION public.resolve_platform_user_id()
RETURNS UUID
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT id
      FROM public.profiles
      WHERE id = '2ef7f269-b36e-4903-ab2d-72b2a74ca28e'::uuid
      LIMIT 1
    ),
    (
      SELECT id
      FROM public.profiles
      WHERE role = 'admin'
      ORDER BY created_at ASC
      LIMIT 1
    )
  );
$$;
CREATE OR REPLACE FUNCTION public.run_order_ops_maintenance()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_platform_user_id UUID;
  v_preparing_result JSONB := '{}'::jsonb;
  v_confirmation_timeouts INTEGER := 0;
  v_stuck_result JSONB := '{}'::jsonb;
  v_result JSONB := '{}'::jsonb;
BEGIN
  v_platform_user_id := public.resolve_platform_user_id();
  v_preparing_result := COALESCE(
    public.process_preparing_orders(),
    '{}'::jsonb
  );
  v_confirmation_timeouts := COALESCE(
    public.process_restaurant_confirmation_timeouts(),
    0
  );
  v_stuck_result := COALESCE(
    public.process_stuck_orders(v_platform_user_id),
    '{}'::jsonb
  );

  v_result := jsonb_build_object(
    'success', true,
    'platform_user_id', v_platform_user_id,
    'preparing', v_preparing_result,
    'restaurant_confirmation_timeouts', v_confirmation_timeouts,
    'stuck_orders', v_stuck_result
  );

  IF to_regclass('public.cron_runs') IS NOT NULL THEN
    INSERT INTO public.cron_runs (
      job_name,
      status,
      details,
      ran_at
    ) VALUES (
      'order_ops_maintenance',
      'completed',
      v_result,
      NOW()
    );
  END IF;

  RETURN v_result;
EXCEPTION
  WHEN OTHERS THEN
    IF to_regclass('public.cron_runs') IS NOT NULL THEN
      INSERT INTO public.cron_runs (
        job_name,
        status,
        details,
        ran_at
      ) VALUES (
        'order_ops_maintenance',
        'failed',
        jsonb_build_object(
          'success', false,
          'error', SQLERRM
        ),
        NOW()
      );
    END IF;
    RAISE;
END;
$$;
REVOKE ALL ON FUNCTION public.run_order_ops_maintenance() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.run_order_ops_maintenance() TO service_role;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_extension
    WHERE extname = 'pg_cron'
  ) THEN
    IF EXISTS (
      SELECT 1
      FROM cron.job
      WHERE jobname = 'deligo-order-ops-maintenance'
    ) THEN
      PERFORM cron.unschedule('deligo-order-ops-maintenance');
    END IF;

    PERFORM cron.schedule(
      'deligo-order-ops-maintenance',
      '* * * * *',
      $cron$
        SELECT public.run_order_ops_maintenance();
      $cron$
    );
  END IF;
END;
$$;
COMMIT;
