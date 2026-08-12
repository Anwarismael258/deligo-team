BEGIN;
DELETE FROM public.account_deletion_requests
WHERE lower(COALESCE(email, '')) LIKE '%@example.com';
UPDATE public.profiles
SET
  kyc_status = 'approved',
  kyc_completed = true,
  kyc_rejection_reason = NULL,
  updated_at = NOW()
WHERE role IN ('courier', 'restaurant')
  AND COALESCE(kyc_status, 'pending') = 'pending';
COMMIT;
