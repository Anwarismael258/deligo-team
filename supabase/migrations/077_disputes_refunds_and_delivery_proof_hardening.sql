BEGIN;
INSERT INTO storage.buckets (id, name, public)
SELECT 'delivery-proofs', 'delivery-proofs', true
WHERE NOT EXISTS (
  SELECT 1 FROM storage.buckets WHERE id = 'delivery-proofs'
);
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'delivery_proofs_upload_own'
  ) THEN
    CREATE POLICY delivery_proofs_upload_own
      ON storage.objects
      FOR INSERT
      TO authenticated
      WITH CHECK (
        bucket_id = 'delivery-proofs'
        AND name LIKE ('proofs/' || auth.uid()::text || '/%')
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'delivery_proofs_update_own'
  ) THEN
    CREATE POLICY delivery_proofs_update_own
      ON storage.objects
      FOR UPDATE
      TO authenticated
      USING (
        bucket_id = 'delivery-proofs'
        AND name LIKE ('proofs/' || auth.uid()::text || '/%')
      )
      WITH CHECK (
        bucket_id = 'delivery-proofs'
        AND name LIKE ('proofs/' || auth.uid()::text || '/%')
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'delivery_proofs_select_related'
  ) THEN
    CREATE POLICY delivery_proofs_select_related
      ON storage.objects
      FOR SELECT
      TO authenticated
      USING (
        bucket_id = 'delivery-proofs'
      );
  END IF;
END $$;
ALTER TABLE IF EXISTS public.profiles
  ADD COLUMN IF NOT EXISTS duplicate_phone_accounts INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS refund_risk_score INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS false_claim_score INTEGER DEFAULT 0;
CREATE OR REPLACE FUNCTION public.refresh_duplicate_phone_flags(p_phone TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_phone TEXT;
BEGIN
  v_target_phone := NULLIF(regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g'), '');

  WITH normalized AS (
    SELECT
      id,
      NULLIF(regexp_replace(COALESCE(phone, ''), '\D', '', 'g'), '') AS normalized_phone
    FROM public.profiles
  ),
  counts AS (
    SELECT normalized_phone, COUNT(*) AS total_accounts
    FROM normalized
    WHERE normalized_phone IS NOT NULL
      AND (v_target_phone IS NULL OR normalized_phone = v_target_phone)
    GROUP BY normalized_phone
  )
  UPDATE public.profiles p
  SET duplicate_phone_accounts = COALESCE(c.total_accounts, 0),
      is_suspicious = CASE
        WHEN COALESCE(c.total_accounts, 0) >= 2 THEN TRUE
        ELSE p.is_suspicious
      END,
      is_blocked = CASE
        WHEN COALESCE(c.total_accounts, 0) >= 3 THEN TRUE
        ELSE p.is_blocked
      END,
      block_reason = CASE
        WHEN COALESCE(c.total_accounts, 0) >= 3 THEN 'Conta bloqueada por múltiplos perfis com o mesmo número.'
        ELSE p.block_reason
      END,
      updated_at = NOW()
  FROM normalized n
  LEFT JOIN counts c ON c.normalized_phone = n.normalized_phone
  WHERE p.id = n.id
    AND (v_target_phone IS NULL OR n.normalized_phone = v_target_phone);

  RETURN jsonb_build_object('success', true, 'phone', v_target_phone);
END;
$$;
CREATE OR REPLACE FUNCTION public.trg_refresh_duplicate_phone_flags()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.refresh_duplicate_phone_flags(NEW.phone);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_refresh_duplicate_phone_flags ON public.profiles;
CREATE TRIGGER trg_refresh_duplicate_phone_flags
AFTER INSERT OR UPDATE OF phone ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.trg_refresh_duplicate_phone_flags();
SELECT public.refresh_duplicate_phone_flags(NULL);
CREATE OR REPLACE FUNCTION public.reverse_order_financial_ledger(
  p_order_id UUID,
  p_reason TEXT DEFAULT 'refund_or_cancellation'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row RECORD;
  v_reversed_count INTEGER := 0;
BEGIN
  FOR v_row IN
    SELECT *
    FROM public.wallet_ledger
    WHERE order_id = p_order_id
      AND status = 'confirmed'
      AND entry_type IN (
        'order_payment_escrow',
        'escrow_reserved',
        'restaurant_confirmation_settlement',
        'courier_settlement',
        'platform_fee_settlement',
        'escrow_release'
      )
  LOOP
    UPDATE public.wallet_ledger
    SET status = 'reversed',
        metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
          'reversed_at', NOW(),
          'reverse_reason', p_reason
        )
    WHERE id = v_row.id
      AND status = 'confirmed';

    v_reversed_count := v_reversed_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'reversed_entries', v_reversed_count
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.register_refund_risk(
  p_user_id UUID,
  p_order_id UUID,
  p_refund_amount NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_refunds_30d INTEGER := 0;
BEGIN
  SELECT COUNT(*)
  INTO v_refunds_30d
  FROM public.refunds
  WHERE user_id = p_user_id
    AND created_at >= NOW() - INTERVAL '30 days';

  UPDATE public.profiles
  SET refund_risk_score = COALESCE(refund_risk_score, 0) + 5,
      is_suspicious = CASE
        WHEN COALESCE(refund_risk_score, 0) + 5 >= 25 OR v_refunds_30d >= 3 THEN TRUE
        ELSE is_suspicious
      END,
      updated_at = NOW()
  WHERE id = p_user_id;

  PERFORM public.register_user_fraud_event(
    p_user_id,
    'refund_registered',
    1,
    5,
    jsonb_build_object(
      'order_id', p_order_id,
      'refund_amount', p_refund_amount,
      'refunds_last_30d', v_refunds_30d
    )
  );

  RETURN jsonb_build_object('success', true, 'refunds_last_30d', v_refunds_30d);
END;
$$;
CREATE OR REPLACE FUNCTION public.handle_not_received_dispute()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delivery RECORD;
BEGIN
  IF NEW.dispute_type = 'not_received' AND NEW.opened_by_role = 'client' THEN
    SELECT proof_photo_url, proof_taken_at, proof_latitude, proof_longitude, delivered_at
    INTO v_delivery
    FROM public.deliveries
    WHERE order_id = NEW.order_id
    LIMIT 1;

    IF v_delivery.proof_photo_url IS NOT NULL
       OR v_delivery.proof_taken_at IS NOT NULL
       OR v_delivery.delivered_at IS NOT NULL THEN
      UPDATE public.profiles
      SET false_claim_score = COALESCE(false_claim_score, 0) + 15,
          is_suspicious = TRUE,
          updated_at = NOW()
      WHERE id = NEW.opened_by;

      PERFORM public.register_user_fraud_event(
        NEW.opened_by,
        'false_not_received_claim',
        3,
        15,
        jsonb_build_object(
          'order_id', NEW.order_id,
          'dispute_id', NEW.id,
          'proof_photo_url', v_delivery.proof_photo_url,
          'proof_taken_at', v_delivery.proof_taken_at
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_handle_not_received_dispute ON public.order_disputes;
CREATE TRIGGER trg_handle_not_received_dispute
AFTER INSERT ON public.order_disputes
FOR EACH ROW
EXECUTE FUNCTION public.handle_not_received_dispute();
CREATE OR REPLACE FUNCTION public.trg_register_refund_risk()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.reverse_order_financial_ledger(
    NEW.order_id,
    'refund_recorded'
  );

  PERFORM public.register_refund_risk(
    NEW.user_id,
    NEW.order_id,
    COALESCE(NEW.refund_amount, 0)
  );
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_register_refund_risk ON public.refunds;
CREATE TRIGGER trg_register_refund_risk
AFTER INSERT ON public.refunds
FOR EACH ROW
EXECUTE FUNCTION public.trg_register_refund_risk();
CREATE OR REPLACE VIEW public.admin_identity_risk_overview AS
SELECT
  p.id,
  p.full_name,
  p.phone,
  p.role,
  p.duplicate_phone_accounts,
  p.refund_risk_score,
  p.false_claim_score,
  p.fraud_score,
  p.is_suspicious,
  p.is_blocked,
  p.block_reason,
  p.updated_at
FROM public.profiles p
WHERE COALESCE(p.phone, '') <> '';
COMMIT;
