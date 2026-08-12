BEGIN;
CREATE TABLE IF NOT EXISTS public.wallet_balance_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id UUID NOT NULL REFERENCES public.wallets(id) ON DELETE CASCADE,
  user_id UUID NULL,
  actor_user_id UUID NULL,
  actor_role TEXT NULL,
  source TEXT NOT NULL DEFAULT 'direct_update',
  reason TEXT NULL,
  old_balance NUMERIC NOT NULL DEFAULT 0,
  new_balance NUMERIC NOT NULL DEFAULT 0,
  old_available_balance NUMERIC NOT NULL DEFAULT 0,
  new_available_balance NUMERIC NOT NULL DEFAULT 0,
  old_pending_balance NUMERIC NOT NULL DEFAULT 0,
  new_pending_balance NUMERIC NOT NULL DEFAULT 0,
  old_locked_balance NUMERIC NOT NULL DEFAULT 0,
  new_locked_balance NUMERIC NOT NULL DEFAULT 0,
  delta_balance NUMERIC NOT NULL DEFAULT 0,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_wallet_balance_audit_wallet_created
  ON public.wallet_balance_audit(wallet_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_balance_audit_user_created
  ON public.wallet_balance_audit(user_id, created_at DESC);
ALTER TABLE public.wallet_balance_audit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS wallet_balance_audit_select_admin ON public.wallet_balance_audit;
CREATE POLICY wallet_balance_audit_select_admin
ON public.wallet_balance_audit
FOR SELECT TO authenticated
USING (public.is_admin());
DROP POLICY IF EXISTS wallet_balance_audit_service_all ON public.wallet_balance_audit;
CREATE POLICY wallet_balance_audit_service_all
ON public.wallet_balance_audit
FOR ALL TO service_role
USING (true)
WITH CHECK (true);
CREATE OR REPLACE FUNCTION public.audit_wallet_balance_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_user_id UUID := auth.uid();
  v_actor_role TEXT;
  v_source TEXT := COALESCE(
    current_setting('request.headers', true)::jsonb ->> 'x-wallet-update-source',
    'direct_update'
  );
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;

  IF
    COALESCE(OLD.balance, 0) IS NOT DISTINCT FROM COALESCE(NEW.balance, 0)
    AND COALESCE(OLD.available_balance, 0) IS NOT DISTINCT FROM COALESCE(NEW.available_balance, 0)
    AND COALESCE(OLD.pending_balance, 0) IS NOT DISTINCT FROM COALESCE(NEW.pending_balance, 0)
    AND COALESCE(OLD.locked_balance, 0) IS NOT DISTINCT FROM COALESCE(NEW.locked_balance, 0)
  THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(
    auth.jwt() ->> 'role',
    auth.jwt() -> 'app_metadata' ->> 'role',
    auth.jwt() -> 'user_metadata' ->> 'role'
  )
  INTO v_actor_role;

  INSERT INTO public.wallet_balance_audit (
    wallet_id,
    user_id,
    actor_user_id,
    actor_role,
    source,
    old_balance,
    new_balance,
    old_available_balance,
    new_available_balance,
    old_pending_balance,
    new_pending_balance,
    old_locked_balance,
    new_locked_balance,
    delta_balance,
    metadata
  )
  VALUES (
    NEW.id,
    NEW.user_id,
    v_actor_user_id,
    v_actor_role,
    v_source,
    COALESCE(OLD.balance, 0),
    COALESCE(NEW.balance, 0),
    COALESCE(OLD.available_balance, 0),
    COALESCE(NEW.available_balance, 0),
    COALESCE(OLD.pending_balance, 0),
    COALESCE(NEW.pending_balance, 0),
    COALESCE(OLD.locked_balance, 0),
    COALESCE(NEW.locked_balance, 0),
    ROUND((COALESCE(NEW.balance, 0) - COALESCE(OLD.balance, 0))::numeric, 2),
    jsonb_build_object(
      'updated_at_before', OLD.updated_at,
      'updated_at_after', NEW.updated_at
    )
  );

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_audit_wallet_balance_changes ON public.wallets;
CREATE TRIGGER trg_audit_wallet_balance_changes
AFTER UPDATE ON public.wallets
FOR EACH ROW
EXECUTE FUNCTION public.audit_wallet_balance_changes();
CREATE OR REPLACE VIEW public.wallet_reconciliation_view AS
SELECT
  w.id AS wallet_id,
  w.user_id,
  p.full_name,
  p.phone,
  p.role,
  COALESCE(w.balance, 0) AS wallet_balance,
  COALESCE(w.available_balance, 0) AS wallet_available_balance,
  COALESCE(w.pending_balance, 0) AS wallet_pending_balance,
  COALESCE((
    SELECT ROUND(COALESCE(SUM(l.amount), 0)::numeric, 2)
    FROM public.wallet_ledger l
    WHERE l.wallet_id = w.id
      AND l.entry_type = 'deposit_net'
      AND l.status = 'confirmed'
  ), 0) AS confirmed_deposit_net_total,
  COALESCE((
    SELECT ROUND(COALESCE(SUM(l.amount), 0)::numeric, 2)
    FROM public.wallet_ledger l
    WHERE l.wallet_id = w.id
      AND l.reference_key LIKE 'manual-%'
      AND l.status = 'confirmed'
  ), 0) AS manual_adjustment_total,
  ROUND((
    COALESCE(w.balance, 0) -
    COALESCE((
      SELECT SUM(l.amount)
      FROM public.wallet_ledger l
      WHERE l.wallet_id = w.id
        AND l.entry_type = 'deposit_net'
        AND l.status = 'confirmed'
    ), 0)
  )::numeric, 2) AS wallet_minus_confirmed_deposits
FROM public.wallets w
LEFT JOIN public.profiles p
  ON p.id = w.user_id;
GRANT SELECT ON public.wallet_reconciliation_view TO authenticated;
GRANT SELECT ON public.wallet_reconciliation_view TO service_role;
COMMIT;
