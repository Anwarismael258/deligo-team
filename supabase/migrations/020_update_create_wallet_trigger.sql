-- Align create_wallet_for_user with current wallets table shape

CREATE OR REPLACE FUNCTION public.create_wallet_for_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.wallets w WHERE w.user_id = NEW.id) THEN
    INSERT INTO public.wallets (
      user_id,
      owner_id,
      balance,
      balance_bigint,
      locked_balance
    )
    VALUES (
      NEW.id,
      NEW.id,
      0,
      0,
      0
    );
  END IF;
  RETURN NEW;
END;
$function$;
