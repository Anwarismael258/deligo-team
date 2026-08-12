BEGIN;
CREATE OR REPLACE FUNCTION public.enforce_order_access_for_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_profile RECORD;
  v_cancel_count INTEGER := 0;
BEGIN
  SELECT id, is_blocked, is_suspicious, block_reason
  INTO v_profile
  FROM public.profiles
  WHERE id = COALESCE(NEW.client_id, NEW.customer_id)
  LIMIT 1;

  IF v_profile.is_blocked THEN
    RAISE EXCEPTION 'account_blocked:%', COALESCE(v_profile.block_reason, 'Conta bloqueada');
  END IF;

  SELECT COUNT(*)
  INTO v_cancel_count
  FROM public.orders
  WHERE (client_id = COALESCE(NEW.client_id, NEW.customer_id) OR customer_id = COALESCE(NEW.client_id, NEW.customer_id))
    AND status = 'cancelled'
    AND created_at >= now() - interval '24 hours'
    AND COALESCE(cancellation_reason, 'customer_cancellation') NOT IN (
      'restaurant_timeout',
      'system_timeout'
    );

  IF v_cancel_count >= 3 THEN
    PERFORM public.register_user_fraud_event(
      COALESCE(NEW.client_id, NEW.customer_id),
      'too_many_daily_cancellations',
      20,
      'high',
      jsonb_build_object('cancel_count_24h', v_cancel_count)
    );
    RAISE EXCEPTION 'daily_cancellation_limit_reached';
  END IF;

  RETURN NEW;
END;
$$;
COMMIT;
