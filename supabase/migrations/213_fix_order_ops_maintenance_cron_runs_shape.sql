BEGIN;
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
  v_cron_has_scheduled_at BOOLEAN := FALSE;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'cron_runs'
      AND column_name = 'scheduled_at'
  )
  INTO v_cron_has_scheduled_at;

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
    IF v_cron_has_scheduled_at THEN
      INSERT INTO public.cron_runs (
        job_name,
        scheduled_at,
        status,
        details,
        ran_at
      ) VALUES (
        'order_ops_maintenance',
        NOW(),
        'completed',
        v_result,
        NOW()
      );
    ELSE
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
  END IF;

  RETURN v_result;
EXCEPTION
  WHEN OTHERS THEN
    IF to_regclass('public.cron_runs') IS NOT NULL THEN
      IF v_cron_has_scheduled_at THEN
        INSERT INTO public.cron_runs (
          job_name,
          scheduled_at,
          status,
          details,
          ran_at
        ) VALUES (
          'order_ops_maintenance',
          NOW(),
          'failed',
          jsonb_build_object(
            'success', false,
            'error', SQLERRM
          ),
          NOW()
        );
      ELSE
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
    END IF;
    RAISE;
END;
$$;
COMMIT;
