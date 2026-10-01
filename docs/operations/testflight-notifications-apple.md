# iOS Activity Push Acceptance

Native project: `dzyitinagewdfkzjkuiz`. Rules: `docs/contracts/content_notifications.md`.

## Verified APNs Connectivity

On 2026-10-01, the targeted cloud probe reached the user's current TestFlight installation; the user confirmed receipt. Production key `8FGN36W96F`, team `YPCJA6K48J`, topic `today.bsmart.ios` remain in protected Edge secrets. The temporary probe function/secret were removed. This verifies APNs connectivity, not every future product notification.

## Immediate Activity Rollout

1. The user manually applies `supabase/ios-account/supabase/migrations/202610010002_immediate_activity_push.sql`, then `202610010003_activity_push_compatibility.sql`, then `202610010004_native_social_push_follow.sql` to the native project after existing notification/cloud/subject/native schemas. Apply in order; the repair fixes real `payload.items` pages and earlier draft trigger/continuation/baseline omissions. It starts disabled and seeds identities, not historical deliveries.
2. Deploy from `supabase/ios-account`: `supabase functions deploy bsmart-push --project-ref dzyitinagewdfkzjkuiz --no-verify-jwt`. The function verifies its separate Vault bearer; unauthenticated POST must return 401.
3. Read back four private tables, four source triggers, service-only RPCs and one cron job scheduled `* * * * *`. Report only aggregate counts/booleans, never tokens, bodies or interests. Seed observed metrics with `services/client_api/.venv/bin/python -m services.client_api.sync_push_returns --apply` (DML only).
4. Set publisher `BSMART_ACTIVITY_PUSH_ENABLED=true`, keep legacy `BSMART_UPDATE_PUSH_ENABLED=false` and mode `cloud`. Enable service-only `bsmart_activity_push_configure(true)` and protected cloud `BSMART_CLOUD_PUSH_ENABLED=true` after readback. Existing App handles `content_update`; platform/native notifications work without rebuilding. Government/celebrity/institution follows require the updated App's subject-interest sync; publish a new TestFlight build for those follows to reach the server.
5. Observe a real new publication; do not fabricate research or trades. Top two followed subjects each receive one original-text notice; verified native operations and later posts send independently. Rescores, rollback, duplicates, hidden profiles and unverified executions send none.

## Verification And Operations

The user applied all three new migrations; readback confirmed four source triggers, the minute cron, repaired trigger bodies, social-follow matching, 22,305 baseline identities and 251 observed platform returns. The new worker was deployed, unauthenticated invocation rejected (401), and its disabled invocation returned attempted=0. Both database/cloud gates and the protected local publisher flag have been enabled; a subsequent authenticated invocation returned HTTP 200 processed with attempted=0 and an empty queue. Eighteen service/SQL tests, 39 Python tests and four iOS ContentPush tests passed. No fake events or trades were used; no genuine post-activation event has yet been used for phone-display acceptance. This turn has not uploaded a new TestFlight build.

Run the four Deno cloud/activity tests plus Python `test_push_returns.py`, existing notification/publication tests. Verify 24/160 grapheme bounds (including ellipsis), original structured disclosures, actual filled amounts and correct closing direction. Distinct notices have distinct collapse IDs.

Check unfollow, category/master switch, account change and profile hiding cancel pending eligibility. Latest production device interests are authoritative. Development registrations require a separate Sandbox key.

Pause both database configure(false) and cloud master false before rollback. Legacy enqueue remains false; do not run a local sender. Monitor pending age/count, accepted/failed/skipped totals and unreclaimed sending rows. Continuations drain bounded batches; cron is fallback, not a daily slot. Expiry is 24 hours. Apple 200 confirms acceptance, not every display. Historical subject imports set transaction-local `bsmart.push_suppress=true`.

A single explicitly authorized device probe uses `python -m services.client_api.probe_cloud_push --handle <exact-handle>` then `--apply` once. It targets the latest fresh production registration and cleans temporary resources. Never repeat uncertain sends without authorization.

The former three fixed daily digest windows are superseded by immediate activity dispatch. Credentials stay in protected secrets; local p8 backups remain outside the repository.
