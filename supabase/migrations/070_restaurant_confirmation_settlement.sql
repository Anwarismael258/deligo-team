BEGIN;
CREATE OR REPLACE FUNCTION public.sync_payment_split_on_restaurant_confirmation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_split RECORD;
  v_order RECORD;
  v_restaurant_owner_id UUID;
  v_restaurant_wallet RECORD;
  v_restaurant_before NUMERIC;
  v_restaurant_after NUMERIC;
BEGIN
  IF NEW.status = 'accepted' AND COALESCE(OLD.status, '') <> 'accepted' THEN
    SELECT *
    INTO v_split
    FROM public.payment_splits
    WHERE order_id = NEW.id
    FOR UPDATE;

    IF FOUND AND COALESCE(v_split.status, '') = 'escrowed' THEN
      SELECT id, restaurant_id
      INTO v_order
      FROM public.orders
      WHERE id = NEW.id;

      SELECT owner_id
      INTO v_restaurant_owner_id
      FROM public.restaurants
      WHERE id = v_order.restaurant_id;

      IF v_restaurant_owner_id IS NOT NULL AND COALESCE(v_split.restaurant_amount, 0) > 0 THEN
        SELECT id, balance
        INTO v_restaurant_wallet
        FROM public.wallets
        WHERE user_id = v_restaurant_owner_id
        FOR UPDATE;

        IF NOT FOUND THEN
          INSERT INTO public.wallets (user_id, balance, currency, is_active, created_at, updated_at)
          VALUES (v_restaurant_owner_id, 0, 'MZN', TRUE, NOW(), NOW())
          RETURNING id, balance INTO v_restaurant_wallet;
        END IF;

        v_restaurant_before := COALESCE(v_restaurant_wallet.balance, 0);
        v_restaurant_after := ROUND((v_restaurant_before + COALESCE(v_split.restaurant_amount, 0))::numeric, 2);

        UPDATE public.wallets
        SET balance = v_restaurant_after,
            updated_at = NOW()
        WHERE id = v_restaurant_wallet.id;

        INSERT INTO public.wallet_ledger (
          wallet_id, user_id, order_id, direction, entry_type,
          amount, balance_before, balance_after, metadata
        ) VALUES (
          v_restaurant_wallet.id,
          v_restaurant_owner_id,
          NEW.id,
          'credit',
          'restaurant_confirmation_settlement',
          COALESCE(v_split.restaurant_amount, 0),
          v_restaurant_before,
          v_restaurant_after,
          jsonb_build_object(
            'source', 'escrow',
            'stage', 'restaurant_confirmation',
            'platform_food_fee', COALESCE(v_split.restaurant_platform_fee, 0)
          )
        );
      END IF;

      UPDATE public.payment_splits
      SET status = 'restaurant_confirmed',
          restaurant_confirmed_at = COALESCE(restaurant_confirmed_at, NOW())
      WHERE order_id = NEW.id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
COMMIT;
