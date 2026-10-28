# Central employee PaySuite payouts

Activated after explicit CEO approval on 29 October 2026. Existing `admin-corporate-withdrawal` now handles `central_employee_payout` and `central_employee_reconcile`; its existing corporate payout body remains unchanged.

Production configuration: `HQ_EMPLOYEE_PAYOUT_READY=true`, `HQ_EMPLOYEE_PAYOUT_ENDPOINT=admin-corporate-withdrawal`. Provider credentials stay in Supabase. Edge version 7 validates bearer tokens with `auth.getUser` and scopes each dispatch to the authenticated active employee, protected verified phone and reserved payout.

Validation: owner isolation, duplicate prevention, pending and timeout handling, provider reconciliation matching reference/amount/destination, canonical Sara balance and legacy exclusion tests passed. A transaction rolled back after preparing CEO 10 MZN, claiming 9.70 MZN net and confirming a duplicate claim cannot dispatch twice. No external payment was initiated during verification.

The profile API reconciles provider status on load; while a personal payout is reserved the profile refreshes every five seconds. Completion debits the reservation, definitive rejection releases it, and ambiguous responses keep it reserved.
