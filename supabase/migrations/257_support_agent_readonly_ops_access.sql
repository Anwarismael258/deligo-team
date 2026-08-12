-- Read-only operational access for support agents.
-- Support can inspect tickets, orders, restaurants and couriers, but does not
-- get KYC approval, field operations, finance or team-management privileges.

DO $$
BEGIN
  IF to_regclass('public.order_disputes') IS NOT NULL THEN
    ALTER TABLE public.order_disputes ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS order_disputes_select_support_staff ON public.order_disputes;
    CREATE POLICY order_disputes_select_support_staff
      ON public.order_disputes
      FOR SELECT
      TO authenticated
      USING (public.is_deligo_field_staff(ARRAY['admin', 'support_agent']));

    GRANT SELECT ON public.order_disputes TO authenticated;
  END IF;

  IF to_regclass('public.orders') IS NOT NULL THEN
    ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS orders_select_support_staff ON public.orders;
    CREATE POLICY orders_select_support_staff
      ON public.orders
      FOR SELECT
      TO authenticated
      USING (public.is_deligo_field_staff(ARRAY['admin', 'support_agent']));

    GRANT SELECT ON public.orders TO authenticated;
  END IF;

  IF to_regclass('public.restaurants') IS NOT NULL THEN
    ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS restaurants_select_support_staff ON public.restaurants;
    CREATE POLICY restaurants_select_support_staff
      ON public.restaurants
      FOR SELECT
      TO authenticated
      USING (public.is_deligo_field_staff(ARRAY['admin', 'support_agent']));

    GRANT SELECT ON public.restaurants TO authenticated;
  END IF;

  IF to_regclass('public.couriers') IS NOT NULL THEN
    ALTER TABLE public.couriers ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS couriers_select_support_staff ON public.couriers;
    CREATE POLICY couriers_select_support_staff
      ON public.couriers
      FOR SELECT
      TO authenticated
      USING (public.is_deligo_field_staff(ARRAY['admin', 'support_agent']));

    GRANT SELECT ON public.couriers TO authenticated;
  END IF;
END $$;
