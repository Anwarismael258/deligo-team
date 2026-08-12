BEGIN;
DO $$
DECLARE
  v_keep_restaurant_id UUID := '311976ef-cc82-45fe-8858-627df6a3c9b7';
  v_keep_anwar_id UUID := '680a7827-68fe-49fa-b005-62e148a6e2b4';
BEGIN
  -- Event-driven operational history
  IF to_regclass('public.order_event_dispatch_attempts') IS NOT NULL THEN
    DELETE FROM public.order_event_dispatch_attempts;
  END IF;

  IF to_regclass('public.order_event_dispatch_jobs') IS NOT NULL THEN
    DELETE FROM public.order_event_dispatch_jobs;
  END IF;

  IF to_regclass('public.push_notifications') IS NOT NULL THEN
    DELETE FROM public.push_notifications;
  END IF;

  IF to_regclass('public.notifications') IS NOT NULL THEN
    DELETE FROM public.notifications;
  END IF;

  IF to_regclass('public.order_events') IS NOT NULL THEN
    DELETE FROM public.order_events;
  END IF;

  -- Chats and delivery traces
  IF to_regclass('public.chat_messages') IS NOT NULL THEN
    DELETE FROM public.chat_messages;
  END IF;

  IF to_regclass('public.chat_members') IS NOT NULL THEN
    DELETE FROM public.chat_members;
  END IF;

  IF to_regclass('public.chats') IS NOT NULL THEN
    DELETE FROM public.chats;
  END IF;

  IF to_regclass('public.messages') IS NOT NULL THEN
    DELETE FROM public.messages;
  END IF;

  IF to_regclass('public.courier_locations') IS NOT NULL THEN
    DELETE FROM public.courier_locations;
  END IF;

  IF to_regclass('public.delivery_override_logs') IS NOT NULL THEN
    DELETE FROM public.delivery_override_logs;
  END IF;

  IF to_regclass('public.order_disputes') IS NOT NULL THEN
    DELETE FROM public.order_disputes;
  END IF;

  IF to_regclass('public.courier_reviews') IS NOT NULL THEN
    DELETE FROM public.courier_reviews;
  END IF;

  IF to_regclass('public.reviews') IS NOT NULL THEN
    DELETE FROM public.reviews;
  END IF;

  IF to_regclass('public.deliveries') IS NOT NULL THEN
    DELETE FROM public.deliveries;
  END IF;

  -- Order and payment history
  IF to_regclass('public.payment_splits') IS NOT NULL THEN
    DELETE FROM public.payment_splits;
  END IF;

  IF to_regclass('public.payments') IS NOT NULL THEN
    DELETE FROM public.payments;
  END IF;

  IF to_regclass('public.webhook_events') IS NOT NULL THEN
    DELETE FROM public.webhook_events;
  END IF;

  IF to_regclass('public.order_items') IS NOT NULL THEN
    DELETE FROM public.order_items;
  END IF;

  IF to_regclass('public.orders') IS NOT NULL THEN
    DELETE FROM public.orders;
  END IF;

  -- Financial and wallet history
  IF to_regclass('public.order_financial_snapshots') IS NOT NULL THEN
    DELETE FROM public.order_financial_snapshots;
  END IF;

  IF to_regclass('public.payouts') IS NOT NULL THEN
    DELETE FROM public.payouts;
  END IF;

  IF to_regclass('public.wallet_ledger') IS NOT NULL THEN
    DELETE FROM public.wallet_ledger;
  END IF;

  IF to_regclass('public.wallet_deposits') IS NOT NULL THEN
    DELETE FROM public.wallet_deposits;
  END IF;

  IF to_regclass('public.withdrawal_requests') IS NOT NULL THEN
    DELETE FROM public.withdrawal_requests;
  END IF;

  IF to_regclass('public.idempotency_keys') IS NOT NULL THEN
    DELETE FROM public.idempotency_keys;
  END IF;

  IF to_regclass('public.financial_ledger_entries') IS NOT NULL THEN
    ALTER TABLE public.financial_ledger_entries
      DISABLE TRIGGER trg_prevent_financial_ledger_delete;

    DELETE FROM public.financial_ledger_entries;

    ALTER TABLE public.financial_ledger_entries
      ENABLE TRIGGER trg_prevent_financial_ledger_delete;
  END IF;

  -- User-side operational leftovers
  IF to_regclass('public.cart_items') IS NOT NULL THEN
    DELETE FROM public.cart_items;
  END IF;

  IF to_regclass('public.favorites') IS NOT NULL THEN
    DELETE FROM public.favorites;
  END IF;

  IF to_regclass('public.user_addresses') IS NOT NULL THEN
    DELETE FROM public.user_addresses;
  END IF;

  IF to_regclass('public.account_deletion_requests') IS NOT NULL THEN
    DELETE FROM public.account_deletion_requests;
  END IF;

  IF to_regclass('public.restaurant_share_events') IS NOT NULL THEN
    DELETE FROM public.restaurant_share_events;
  END IF;

  IF to_regclass('public.restaurant_shares') IS NOT NULL THEN
    DELETE FROM public.restaurant_shares;
  END IF;

  IF to_regclass('public.restaurant_referral_rewards') IS NOT NULL THEN
    DELETE FROM public.restaurant_referral_rewards;
  END IF;

  -- Restaurant baseline: keep only the active restaurant and its menu
  IF to_regclass('public.daily_combos') IS NOT NULL THEN
    DELETE FROM public.daily_combos
    WHERE restaurant_id IS DISTINCT FROM v_keep_restaurant_id;
  END IF;

  IF to_regclass('public.menu_item_reviews') IS NOT NULL THEN
    DELETE FROM public.menu_item_reviews;
  END IF;

  IF to_regclass('public.menu_items') IS NOT NULL THEN
    DELETE FROM public.menu_items
    WHERE restaurant_id IS DISTINCT FROM v_keep_restaurant_id;
  END IF;

  IF to_regclass('public.menus') IS NOT NULL THEN
    DELETE FROM public.menus
    WHERE restaurant_id IS DISTINCT FROM v_keep_restaurant_id;
  END IF;

  IF to_regclass('public.restaurants') IS NOT NULL THEN
    DELETE FROM public.restaurants
    WHERE id IS DISTINCT FROM v_keep_restaurant_id
       OR owner_id IS NULL;
  END IF;

  -- Final wallet state for real delivery testing
  IF to_regclass('public.wallets') IS NOT NULL THEN
    UPDATE public.wallets
    SET
      balance = CASE WHEN user_id = v_keep_anwar_id THEN 209.00 ELSE 0.00 END,
      available_balance = CASE WHEN user_id = v_keep_anwar_id THEN 209.00 ELSE 0.00 END,
      pending_balance = 0.00,
      updated_at = NOW();
  END IF;
END $$;
COMMIT;
