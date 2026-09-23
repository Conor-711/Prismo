# iOS content push acceptance

The native iOS Supabase project is `dzyitinagewdfkzjkuiz`. The previous content-release notification was a generic, per-revision broadcast. The new path uses a per-user, per-content ledger and sends at most one digest at 08:00, 18:00, and 22:00 Asia/Shanghai. See `docs/contracts/content_notifications.md`.

## One-time rollout

1. The user manually applies `supabase/ios-account/supabase/migrations/202609230001_interest_push.sql` in that project's SQL Editor after `202609160001_content_notifications.sql`. Do not point it at the web Supabase project. Verify both new tables, device interest columns, and `bsmart_set_push_interests` via read-only catalog queries.
2. Deploy the updated `bsmart-notifications` Edge Function and verify that an unauthenticated `/interests` call returns 401. Authenticate on a real iPhone, allow notifications, and confirm the device and its interest snapshot are registered. Never expose APNs tokens or holding tickers in logs or chat.
3. Configure `BSMART_CONTENT_DATABASE_URL`, `BSMART_UPDATE_PUSH_ENABLED=true`, `BSMART_APNS_TEAM_ID`, `BSMART_APNS_KEY_ID`, `BSMART_APNS_TOPIC=today.bsmart.ios`, and either `BSMART_APNS_PRIVATE_KEY` or protected `BSMART_APNS_PRIVATE_KEY_PATH` on the always-on worker. The Railway service template is `services/client_api/railway.content-push.json`. The publisher also needs `BSMART_UPDATE_PUSH_ENABLED=true` after the migration. Do not commit credentials or the `.p8` file.
4. Install an InternalAlpha/TestFlight build containing `/interests` sync and the three settings toggles. TestFlight uses production APNs; Debug uses development APNs. The existing Apple/Google identity and permission requirements remain.

## Acceptance

- Follow one author, one ticker, and open/record a holding on the iPhone. Read back only normalized interest counts and boolean switches from the protected project, never raw account details in reports.
- Publish a genuinely new opinion and movement using the reviewed content pipeline. Confirm `notificationsQueued` counts unique user/content entries and a score-only re-publish queues zero. Follow + watched ticker + holding matching the same opinion must still create one ledger row.
- At the next fixed slot, inspect one batch for that user and the APNs response. Multiple new items before the slot should produce one count-based notification. No content means no batch. Confirm a maximum of three slot rows per UTC+8 calendar day and no resend after APNs timeout or worker restart.
- Tap the push in foreground/background/cold start: Today refreshes and opens Notifications. Disable each category, disable the master switch, revoke OS permission, switch accounts, sign out, and rotate the APNs token; verify that subscriptions and deliveries do not cross accounts.

APNs HTTP 200 means Apple accepted the request, not that the iPhone displayed it. Verify real-device delivery separately. A timeout or crash after claim is intentionally not retried because the user requested a strict no-duplicate policy; the missed alert will not reappear in a later slot. If the worker is offline past a slot, unsent pending events move to the next slot, provided the user still subscribes. This worker must be continuously running; a local three-hour content upload schedule is not sufficient.
