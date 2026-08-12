BEGIN;
CREATE OR REPLACE FUNCTION public.get_cashback_loyalty_status(
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_eligible_orders INTEGER := 0;
  v_remaining_orders INTEGER := 0;
BEGIN
  SELECT COUNT(*)
  INTO v_eligible_orders
  FROM public.orders
  WHERE COALESCE(client_id, customer_id) = p_user_id
    AND COALESCE(total_amount, total, 0) >= 800
    AND status IN ('delivered', 'completed');

  v_remaining_orders := GREATEST(8 - v_eligible_orders, 0);

  RETURN jsonb_build_object(
    'eligible_orders', v_eligible_orders,
    'remaining_orders', v_remaining_orders,
    'cashback_percent', 10,
    'minimum_order_amount', 800,
    'is_unlocked', v_eligible_orders >= 8,
    'rule', 'all_customers_after_8_orders_above_800'
  );
END;
$$;
COMMIT;
