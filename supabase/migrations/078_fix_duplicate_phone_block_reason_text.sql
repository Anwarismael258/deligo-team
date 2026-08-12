BEGIN;
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
COMMIT;
