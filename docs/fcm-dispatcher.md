# FCM dispatcher

`supabase/functions/push-notification-dispatcher` processes the shared
`public.push_notifications` queue for DeliGo Eats, Mestre24, Comunhão and
other apps that use the common notification ledger.

## Required Supabase secrets

- `FIREBASE_SERVICE_ACCOUNT`: the Firebase service-account JSON, stored only as
  a Supabase Edge Function secret.
- `FCM_DISPATCH_SECRET`: optional secret used to protect manual/cron calls.

The dispatcher uses the existing `user_push_tokens` table, the existing
`claim_pending_push_notifications` RPC and the existing retry/audit columns.
New records are marked `queued`; `pending` remains supported for older rows.

The shared transport already sends:

- high-priority Android messages;
- Android notification channels;
- custom sounds for courier, restaurant and client alerts;
- `default` sound for other system events;
- `default` iOS sound and time-sensitive interruption for urgent events.

The mobile apps must register the corresponding Android notification channels
and include the sound resources (`short_bang` and `platinum_1`). If a sound
resource is absent, the operating system uses its fallback and delivery is
still recorded.

The function does not send anything until it is deployed and the Firebase
secret is configured. No production secret is included in the repository.
