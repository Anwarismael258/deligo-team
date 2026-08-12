-- The auth bootstrap uses ON CONFLICT (user_id) when ensuring a wallet.
-- Production was missing the expected uniqueness guarantee, causing user
-- creation to fail inside the trigger.

ALTER TABLE public.wallets
  ADD CONSTRAINT wallets_user_id_key UNIQUE (user_id);
