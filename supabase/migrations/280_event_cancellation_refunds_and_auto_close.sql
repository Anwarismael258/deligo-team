BEGIN;
ALTER TABLE public.marketing_events
  ADD COLUMN IF NOT EXISTS refunded_tickets INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS refunded_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS refunded_restaurant_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS refunded_commission NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cancellation_reason TEXT,
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;
CREATE TABLE IF NOT EXISTS public.event_ticket_refunds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.marketing_events(id) ON DELETE CASCADE,
  ticket_id UUID NOT NULL UNIQUE REFERENCES public.marketing_event_tickets(id) ON DELETE CASCADE,
  buyer_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  gross_amount NUMERIC(12,2) NOT NULL,
  restaurant_amount NUMERIC(12,2) NOT NULL,
  platform_amount NUMERIC(12,2) NOT NULL,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'completed'
    CHECK (status IN ('pending', 'completed', 'failed', 'reversed')),
  processed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_event_ticket_refunds_event
  ON public.event_ticket_refunds(event_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_event_ticket_refunds_buyer
  ON public.event_ticket_refunds(buyer_id, created_at DESC);
ALTER TABLE public.event_ticket_refunds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS event_ticket_refunds_buyer_select ON public.event_ticket_refunds;
CREATE POLICY event_ticket_refunds_buyer_select
  ON public.event_ticket_refunds FOR SELECT TO authenticated
  USING (buyer_id = auth.uid());
DROP POLICY IF EXISTS event_ticket_refunds_staff_select ON public.event_ticket_refunds;
CREATE POLICY event_ticket_refunds_staff_select
  ON public.event_ticket_refunds FOR SELECT TO authenticated
  USING (public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']));
GRANT SELECT ON public.event_ticket_refunds TO authenticated;
GRANT ALL ON public.event_ticket_refunds TO service_role;
CREATE OR REPLACE FUNCTION public.cancel_marketing_event_and_refund(
  p_event_id UUID,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event public.marketing_events%ROWTYPE;
  v_ticket public.marketing_event_tickets%ROWTYPE;
  v_buyer_wallet public.wallets%ROWTYPE;
  v_restaurant_wallet public.wallets%ROWTYPE;
  v_platform_wallet public.wallets%ROWTYPE;
  v_restaurant_owner_id UUID;
  v_restaurant_name TEXT;
  v_platform_user_id UUID;
  v_refunded_count INTEGER := 0;
  v_total_gross NUMERIC(12,2) := 0;
  v_total_restaurant NUMERIC(12,2) := 0;
  v_total_platform NUMERIC(12,2) := 0;
  v_reason TEXT := NULLIF(trim(p_reason), '');
BEGIN
  IF NOT public.is_deligo_field_staff(ARRAY['admin', 'marketing_agent']) THEN
    RAISE EXCEPTION 'not_allowed_to_cancel_event';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'cancellation_reason_required';
  END IF;

  SELECT * INTO v_event
  FROM public.marketing_events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'event_not_found';
  END IF;
  IF v_event.status = 'cancelled' THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_cancelled', true,
      'event_id', v_event.id,
      'refunded_tickets', v_event.refunded_tickets,
      'refunded_amount', v_event.refunded_amount
    );
  END IF;
  IF v_event.status = 'completed' THEN
    RAISE EXCEPTION 'completed_event_cannot_be_cancelled';
  END IF;

  SELECT owner_id, name
  INTO v_restaurant_owner_id, v_restaurant_name
  FROM public.restaurants
  WHERE id = v_event.restaurant_id;
  v_platform_user_id := public.resolve_platform_user_id();

  IF v_restaurant_owner_id IS NOT NULL THEN
    v_restaurant_wallet := public.ensure_user_wallet(v_restaurant_owner_id, 'MZN');
  END IF;
  IF v_platform_user_id IS NOT NULL THEN
    v_platform_wallet := public.ensure_user_wallet(v_platform_user_id, 'MZN');
  END IF;

  FOR v_ticket IN
    SELECT *
    FROM public.marketing_event_tickets
    WHERE event_id = p_event_id
      AND status = 'sold'
    ORDER BY created_at
    FOR UPDATE
  LOOP
    IF v_ticket.buyer_id IS NOT NULL THEN
      v_buyer_wallet := public.ensure_user_wallet(v_ticket.buyer_id, 'MZN');
      PERFORM public.apply_wallet_ledger_entry(
        p_wallet_id := v_buyer_wallet.id,
        p_user_id := v_ticket.buyer_id,
        p_direction := 'credit',
        p_entry_type := 'event_ticket_refund',
        p_amount := v_ticket.price,
        p_reference_key := 'event-ticket-refund:' || v_ticket.id::text,
        p_metadata := jsonb_build_object(
          'event_id', p_event_id,
          'ticket_id', v_ticket.id,
          'reason', v_reason,
          'source', 'event_cancellation'
        ),
        p_status := 'confirmed',
        p_allow_negative := true
      );
    END IF;

    IF v_restaurant_wallet.id IS NOT NULL AND v_ticket.restaurant_amount > 0 THEN
      PERFORM public.apply_wallet_ledger_entry(
        p_wallet_id := v_restaurant_wallet.id,
        p_user_id := v_restaurant_owner_id,
        p_direction := 'debit',
        p_entry_type := 'event_ticket_restaurant_refund_reversal',
        p_amount := v_ticket.restaurant_amount,
        p_reference_key := 'event-ticket-restaurant-refund:' || v_ticket.id::text,
        p_metadata := jsonb_build_object(
          'event_id', p_event_id,
          'ticket_id', v_ticket.id,
          'buyer_id', v_ticket.buyer_id,
          'reason', v_reason
        ),
        p_status := 'confirmed',
        p_allow_negative := true
      );
    END IF;

    IF v_ticket.deligo_commission > 0 THEN
      PERFORM public.apply_wallet_ledger_entry(
        p_wallet_id := v_platform_wallet.id,
        p_user_id := v_platform_user_id,
        p_direction := 'debit',
        p_entry_type := 'event_ticket_commission_refund_reversal',
        p_amount := v_ticket.deligo_commission,
        p_reference_key := 'event-ticket-platform-refund:' || v_ticket.id::text,
        p_metadata := jsonb_build_object(
          'event_id', p_event_id,
          'ticket_id', v_ticket.id,
          'buyer_id', v_ticket.buyer_id,
          'reason', v_reason
        ),
        p_status := 'confirmed',
        p_allow_negative := true
      );
    END IF;

    UPDATE public.marketing_event_tickets
    SET status = 'cancelled',
        validation_metadata = validation_metadata || jsonb_build_object(
          'cancelled_at', now(),
          'cancellation_reason', v_reason,
          'refund_status', 'completed'
        )
    WHERE id = v_ticket.id;

    INSERT INTO public.event_ticket_refunds (
      event_id, ticket_id, buyer_id, gross_amount, restaurant_amount,
      platform_amount, reason, status, processed_by, metadata
    ) VALUES (
      p_event_id, v_ticket.id, v_ticket.buyer_id, v_ticket.price,
      v_ticket.restaurant_amount, v_ticket.deligo_commission, v_reason,
      'completed', auth.uid(),
      jsonb_build_object('source', 'cancel_marketing_event_and_refund')
    )
    ON CONFLICT (ticket_id) DO NOTHING;

    IF v_ticket.buyer_id IS NOT NULL THEN
      PERFORM public.create_app_notification(
        p_user_id := v_ticket.buyer_id,
        p_type := 'EVENT_CANCELLED_REFUNDED',
        p_title := 'Evento cancelado e reembolsado',
        p_body := 'O evento "' || v_event.title || '" foi cancelado. ' ||
          to_char(v_ticket.price, 'FM999999990.00') || ' MT foram devolvidos a sua Wallet.',
        p_action := 'OPEN_WALLET_TICKETS',
        p_entity_id := v_ticket.id::text,
        p_priority := 'HIGH',
        p_channel := 'marketing',
        p_metadata := jsonb_build_object(
          'event_id', p_event_id,
          'ticket_id', v_ticket.id,
          'refund_amount', v_ticket.price,
          'reason', v_reason
        ),
        p_dispatch_key := 'event-refund:' || v_ticket.id::text
      );
    END IF;

    v_refunded_count := v_refunded_count + 1;
    v_total_gross := v_total_gross + v_ticket.price;
    v_total_restaurant := v_total_restaurant + v_ticket.restaurant_amount;
    v_total_platform := v_total_platform + v_ticket.deligo_commission;
  END LOOP;

  UPDATE public.marketing_events
  SET status = 'cancelled',
      cancellation_reason = v_reason,
      cancelled_at = now(),
      refunded_tickets = refunded_tickets + v_refunded_count,
      refunded_amount = refunded_amount + v_total_gross,
      refunded_restaurant_amount = refunded_restaurant_amount + v_total_restaurant,
      refunded_commission = refunded_commission + v_total_platform,
      updated_at = now()
  WHERE id = p_event_id;

  UPDATE public.marketing_requests
  SET status = 'cancelled',
      revision_notes = v_reason,
      updated_at = now()
  WHERE id = v_event.request_id;

  UPDATE public.event_ticket_types
  SET status = 'cancelled'
  WHERE event_id = p_event_id
    AND status <> 'cancelled';

  UPDATE public.restaurant_event_wallets
  SET balance = balance - v_total_restaurant,
      available_balance = available_balance - v_total_restaurant,
      updated_at = now()
  WHERE event_id = p_event_id;

  IF v_restaurant_owner_id IS NOT NULL THEN
    PERFORM public.create_app_notification(
      p_user_id := v_restaurant_owner_id,
      p_type := 'EVENT_CANCELLED',
      p_title := 'Evento cancelado',
      p_body := '"' || v_event.title || '" foi cancelado. ' ||
        v_refunded_count::text || ' bilhete(s) foram reembolsados.',
      p_action := 'OPEN_RESTAURANT_MARKETING',
      p_entity_id := p_event_id::text,
      p_priority := 'HIGH',
      p_channel := 'marketing',
      p_metadata := jsonb_build_object(
        'event_id', p_event_id,
        'refunded_tickets', v_refunded_count,
        'refunded_amount', v_total_gross,
        'reason', v_reason
      ),
      p_dispatch_key := 'event-cancelled:' || p_event_id::text || ':' || v_restaurant_owner_id::text
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'event_id', p_event_id,
    'status', 'cancelled',
    'refunded_tickets', v_refunded_count,
    'refunded_amount', v_total_gross,
    'restaurant_reversal', v_total_restaurant,
    'platform_reversal', v_total_platform,
    'reason', v_reason
  );
END;
$$;
REVOKE ALL ON FUNCTION public.cancel_marketing_event_and_refund(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_marketing_event_and_refund(UUID, TEXT) TO authenticated;
CREATE OR REPLACE FUNCTION public.close_finished_marketing_events()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  UPDATE public.marketing_events
  SET status = 'completed',
      completed_at = COALESCE(completed_at, now()),
      updated_at = now()
  WHERE status IN ('published', 'sold_out')
    AND event_date + COALESCE(event_end_time, event_time, TIME '23:59:59')
      < timezone('Africa/Maputo', now());
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.close_finished_marketing_events() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.close_finished_marketing_events() TO service_role;
CREATE OR REPLACE FUNCTION public.validate_marketing_event_ticket(p_ticket_code TEXT)
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
  SELECT * INTO v_ticket
  FROM public.marketing_event_tickets
  WHERE ticket_code = upper(trim(p_ticket_code)) OR qr_code = trim(p_ticket_code)
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

  IF v_event.status = 'cancelled' OR v_ticket.status = 'cancelled' THEN
    RETURN jsonb_build_object('success', false, 'error', 'event_cancelled');
  END IF;
  IF v_event.status = 'completed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'event_completed');
  END IF;
  IF v_ticket.status = 'used' THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'ticket_already_used',
      'used_at', v_ticket.used_at, 'validated_by', v_ticket.validated_by
    );
  END IF;
  IF v_ticket.status <> 'sold' THEN
    RETURN jsonb_build_object('success', false, 'error', 'ticket_not_active');
  END IF;

  UPDATE public.marketing_event_tickets
  SET status = 'used', used_at = now(), validated_by = auth.uid(),
      validation_metadata = jsonb_build_object('source', 'restaurant_scanner')
  WHERE id = v_ticket.id;
  UPDATE public.marketing_events
  SET tickets_used = tickets_used + 1
  WHERE id = v_ticket.event_id;
  RETURN jsonb_build_object('success', true, 'event_id', v_ticket.event_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.validate_marketing_event_ticket(TEXT) TO authenticated;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'deligo-close-finished-events') THEN
      PERFORM cron.unschedule('deligo-close-finished-events');
    END IF;
    PERFORM cron.schedule(
      'deligo-close-finished-events',
      '*/15 * * * *',
      $cron$SELECT public.close_finished_marketing_events();$cron$
    );
  END IF;
END;
$$;
SELECT public.close_finished_marketing_events();
COMMIT;
