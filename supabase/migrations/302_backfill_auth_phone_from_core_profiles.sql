-- Backfill canonical phone numbers into Supabase Auth for phone/password login.
-- Conflicting numbers are intentionally skipped: one phone must identify only
-- one auth user.
WITH candidates AS (
  SELECT
    p.user_id,
    '+' || regexp_replace(p.primary_phone, '\D', '', 'g') AS normalized_phone
  FROM core.profiles p
  WHERE nullif(regexp_replace(coalesce(p.primary_phone, ''), '\D', '', 'g'), '') IS NOT NULL
),
safe_candidates AS (
  SELECT c.*
  FROM candidates c
  WHERE NOT EXISTS (
    SELECT 1
    FROM auth.users existing
    WHERE existing.id <> c.user_id
      AND '+' || regexp_replace(coalesce(existing.phone, ''), '\D', '', 'g')
          = c.normalized_phone
  )
  AND NOT EXISTS (
    SELECT 1
    FROM candidates duplicate
    WHERE duplicate.user_id <> c.user_id
      AND duplicate.normalized_phone = c.normalized_phone
  )
)
UPDATE auth.users u
SET
  phone = c.normalized_phone,
  phone_change = '',
  phone_change_token = '',
  phone_change_sent_at = NULL,
  updated_at = now()
FROM safe_candidates c
WHERE u.id = c.user_id
  AND u.phone IS NULL;
