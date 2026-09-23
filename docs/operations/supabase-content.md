# Supabase Content Operations

2026-09-16 (Asia/Shanghai). The native-project connection is configured in the
Git-ignored, mode-0600 local file. First baseline committed successfully at
`2026-09-15T17:01:07.139987+00:00` with revision
`552f23d55534327004028e25e40b90c071e70a752ce5c7d6f34b8b33646e6bb7`.
The previously deployed `bsmart-content` remains the only function changed.
Remote SQL verifies RLS is enabled and anon/authenticated have no table privileges;
service_role has SELECT only. REST reads confirm the active revision. Unsigned
Edge requests and a service-role key used in place of a user return 401.
Real Google/Apple user manifest/page acceptance and device testing remain pending;
no user token was fabricated or extracted to stand in for login. No TestFlight
build was uploaded. The app still defaults to `BSMART_CONTENT_BACKEND=legacy`.

The baseline migrates the reviewed historical exports in `contracts/fixtures`,
also documented as real author/call data by the native Feed catalog workflow.
It is NOT a new daily package: 353 authors (234 X, 88 YouTube, 31 Reddit), 267
updates, 1,204 historical evidence records, 54 Smart Money accounts, 220 movements,
45 money evidence records, and the existing one signal/one ticker-intelligence
record. Source dates are preserved: latest update 2026-09-05, Smart Money snapshot
2026-08-14. Known snapshot checkpoints come from authorScoreAsOf, dataAsOf and
sourceUpdatedAt; publishedAt/observedAt/latestEntryAt supply content timestamps.
The collection checkpoints do not imply every platform was refreshed that day.
Preparation, source-time metadata and publication receipts are stored privately
under `data/runtime/supabase-content-20260916/`. A fresh supplied package must still
go through the daily workflow below.

Readback exposed negative-zero JSONB normalization (`-0.0` became `0.0`): all
380 page payloads and collection values matched, but the old historical-evidence
hash differed. Hashing now normalizes integral floats/negative zero, with focused
regression tests. Repair uses `--baseline --reencode-baseline --apply` with the
identical reviewed input; it retains the first revision and changes no data or
timestamps. Use the latest publication receipt for the active corrected revision.

Corrected revision `f862986a1e0907ba4a3bb433962f8a60fdb90271c4b60fa869a924acd85e6a06`
committed at `2026-09-15T17:20:43.313459+00:00`. All 380 pages were compared against
the reviewed source through paged operator REST reads of the first version and a
server-side full join proving corrected pages identical except for revision.
All eight canonical hashes, counts, preserved timestamps and active pointer pass.
Receipt: `data/runtime/supabase-content-20260916/database-verification.json`.
The initial bulk SQL read ended with OperationalError; bounded reads succeeded.
23 focused Python tests pass after the normalization and explicit-repair change.
These operator checks set databaseVerified=true, not publicAPIVerified or
iOSDeviceVerified. A real signed-in client is still required for those gates.

Local verification: 26 Python publication/API-verifier and legacy daily-publisher
tests, 24 pipeline/boundary tests, 22 Edge/content/search/profile tests, 14 iOS
content/evidence tests and 40 iOS factory/Auth/Feed regression tests passed. Existing
bundled collections pass the new schema/reference checks (compatibility only, not
a fresh publication). Transaction failure tests use an isolated SQLite database;
concurrent-publisher and failure/rollback behavior still needs production
acceptance. No wallet, trade-feed or real user funds were modified. On 2026-09-16,
20 focused configuration/publication/API-verifier tests passed again.

## Scope

Local Python processes the supplied X package. Supabase PostgreSQL stores immutable
research releases; `bsmart-content` serves paginated reads to authenticated iOS.
This replaces the Vultr **research delivery** dependency. It does not move the
Smart Money worker, AI inference, APNs, legacy installation state, or any wallet,
Auth, order and trade-feed service. Native Supabase account/feed and on-chain
execution continue unchanged. User positions, follows and read states remain in
their existing device stores; Supabase content mode does not claim cloud sync for
those private settings. Do not shut down Vultr based only on this migration.

## One-Time Provisioning

1. User reviews and manually executes
   `supabase/ios-account/supabase/migrations/202609150001_research_content.sql`
   in the **native iOS Supabase project**, not the legacy web project. Only three
   `bsmart_content_*` tables are created. No public/anon/authenticated table grants;
   service_role has read-only table grants and RLS bypass for the Edge reader.
2. Deploy only this new function, leaving existing functions unchanged:

   ```sh
   supabase functions deploy bsmart-content --workdir supabase/ios-account --project-ref dzyitinagewdfkzjkuiz --no-verify-jwt --use-api
   ```

   Gateway JWT checks are disabled because the handler calls Auth `getUser` for
   every request and requires a non-anonymous Google/Apple identity. No service key
   or database connection is included in the app. Unsigned/test-login users cannot
   fetch protected content; the existing offline baseline remains available.
3. Install updated `services/client_api/requirements.txt`. Configure
   `BSMART_CONTENT_DATABASE_URL` through a protected environment file with the
   Supabase direct or session-pooler PostgreSQL connection (TLS required). Do not
   put it in commands, Git or chat. No SSH tunnel or public Vultr DB port is needed.
   The publication CLI reads this one key from the process environment first,
   then `services/client_api/.env.content.local`, then the repository `.env`.
   It never substitutes `DATABASE_URL` from the web project. The dedicated local
   file is Git-ignored; restrict its permissions to 0600. Obtain the URI from
   Connect / Session pooler in project `dzyitinagewdfkzjkuiz`; the user fills the
   database password locally, percent-encoding reserved characters. Do not reset
   the database password as part of this setup.
4. Prepare a complete reviewed baseline of all eight exported collections. Do not
   substitute `contracts/fixtures` for today's live publication. A separate source
   metadata file must supply actual `checkedAt` and `latestContentAt` for every
   collection; unknown/latest absent may be null, never fabricated as now:

   ```json
   {"smart-accounts":{"checkedAt":"2026-09-10T00:00:00Z","latestContentAt":null}}
   ```

   This is a shape example, not a complete manifest or a claim about real freshness.
   Other required keys: smart-account-updates, smart-account-evidence,
   portfolio-signals, ticker-intelligence, smart-money, smart-money-movements,
   smart-money-evidence. Evidence includes all platforms and real source-linked
   representative works. Bootstrap with current source exports, preserving each
   platform's true dates; do not label old YouTube/Reddit data as a new X update.

   ```sh
   make content-prepare-baseline INPUT_DIR='/reviewed/export' SOURCE_METADATA='/reviewed/source-times.json' OUTPUT_DIR='/new/baseline'
   make content-publish INPUT_DIR='/new/baseline' BASELINE=1
   make content-publish INPUT_DIR='/new/baseline' BASELINE=1 APPLY=1
   ```

   Preparation performs no database writes. Publication defaults to validation;
   APPLY=1 atomically stores the release and activates it. It refuses to initialize
   from an X-only package, create missing schemas, or overwrite an existing baseline.
5. Verify the API using a real test user's short-lived access token, stored only
   in a protected environment. Set `BSMART_CONTENT_SUPABASE_URL`,
   `BSMART_CONTENT_PUBLISHABLE_KEY`, `BSMART_CONTENT_ACCESS_TOKEN`. Then:

   ```sh
   services/client_api/.venv/bin/python -m services.client_api.content_release.verify --revision EXPECTED_SHA256 --evidence-owner 'x:AUTHOR_ID' --output /private/run/supabase-api-verification.json
   ```

   The verifier checks the exact active revision, schema/count/hash of every main
   collection and optional author's full evidence; it never claims device testing.
6. Only after API verification, archive the next iOS build with
   `BSMART_CONTENT_BACKEND=supabase` (build setting in `ios/project.yml` or an explicit
   xcodebuild override, then regenerate). Old builds keep their old endpoint; a
   one-time TestFlight update is needed for direct Supabase delivery. Future data
   updates with schemaVersion 1 do not require another binary update.

## Daily, or Twice Daily

### Temporary Ranking Freeze (2026-09-23)

Smart Account rankings are pinned to the reviewed September 16 baseline while
opinion content continues to update. The restoration overlays scoring fields on
current author profiles and opinion cards; it does not roll back posts, author
biographies, Smart Money, accounts, or trades. Authors absent from the baseline
retain their current ranking at the first freeze. Subsequent X/YouTube/Reddit
publications carry the frozen snapshot forward, including for first-seen authors.
Automatic X and social-delivery workers still settle individual calls but skip
`score_investors` by default. `BSMART_RANKINGS_FROZEN=false` is the explicit
operator override for processing; unfreezing the published snapshot requires a
separate reviewed publication change. Do not merely toggle the worker variable.

After a dry run, restore once with:

```sh
services/client_api/.venv/bin/python -m services.client_api.content_release \
  --input-dir data/runtime/supabase-content-20260916/baseline --restore-rankings
services/client_api/.venv/bin/python -m services.client_api.content_release \
  --input-dir data/runtime/supabase-content-20260916/baseline --restore-rankings --apply
```

The immutable pre-freeze revision remains available for explicit rollback.
Validate the resulting revision and confirm Serenity is Score 107, X rank 33,
Top 15% before reporting device acceptance.

Same new-package processing and quality gates as `x-daily-package.md`. No new
scheduler or crawler is introduced. Two fresh packages + two successful publishes
provide twice-daily updates; rerunning the same package is deduplicated.

Stop the old X writer; set `X_INGEST_ENABLED=false` and
`BSMART_CONTENT_PUBLISH_TARGET=supabase` in the protected workflow environment.

```sh
make x-daily PACKAGE='/new/x-package.zip'
make x-daily PACKAGE='/new/x-package.zip' APPLY=1 PUBLISH=1 WORKERS=2 MAX_CALLS=1000
```

Or publish an already prepared daily release:

```sh
make content-publish INPUT_DIR='/daily/release'
make content-publish INPUT_DIR='/daily/release' APPLY=1
```

Applied content releases also synchronize the private `bsmart-feed-catalog` from
the active content revision. Check `tradeCatalog.status` and
`tradeCatalog.contentRevision` in `supabase-publication.json` before treating
new opinions as tradeable. A catalog failure does not roll back the already-active
research release; the command exits nonzero and records the pending state. Retry
without republishing content:

```sh
services/client_api/.venv/bin/python -m services.client_api.opinion_trades.publish_catalog --active-content --apply
```

The catalog publisher keeps older opinion IDs for installed clients and activates
the new catalog only after every object upload succeeds. Never bypass the catalog
check on an order to work around a delayed sync.

Repeat API verification above using the returned revision. Report separately:
`ready` (local export), `published` (DB committed), `publicAPIVerified` and
`iOSDeviceVerified`. A healthy endpoint alone is not proof of current content.
Missing prerequisites fail closed; no automatic fallback publication to Vultr.

Each publish preserves non-X rows, other collections and timestamps, checks ID and
author references, OpenAPI models, source age and 25% drop guard. It holds one
transaction-level PostgreSQL advisory lock; the current pointer changes only after
all pages exist. Release ID is content/provenance-derived. Unchanged collections
retain their hash, so iOS downloads only changed main collections. Main snapshots
commit after all decoding succeeds; evidence is paged per account lazily.

App foreground checks run every 60 seconds; closed/suspended apps do not receive
an exact-time refresh guarantee. No automatic historical APNs blast is sent.

## Rollback and Acceptance

```sh
make content-rollback REVISION='PREVIOUS_SHA256'
make content-rollback REVISION='PREVIOUS_SHA256' APPLY=1
```

Rollback changes only the active content pointer, never dates or user data. Old
versions are retained; monitor DB storage and define retention before scaling.
Do not purge a revision clients may be reading. Content deletion must also cover
retained releases; routine package absence is not treated as proof of deletion.

Before rollout: verify RLS rejection for anon/authenticated REST table reads,
401 for unsigned Edge requests, authenticated manifest/page reads, X/YouTube/Reddit
and Smart Money counts, paging and hashes, and representative work navigation.
On one installed iOS build: record old version/data, publish a new package, return
to foreground, confirm new author/statement/time without reinstalling. Confirm
positions/costs/follows/read states and wallet login remain intact. Test offline
reopen, failed publication, API outage, and an explicit rollback.

## 2026-09-22 activation

Build 1.0 (9) now selects Supabase by default and remains live when launched from
the device icon, including the development-signed acceptance build. Real-user
main-collection decoding was confirmed through the device's non-sensitive receipt.
At the user's explicit request, the reviewed September 16 historical package was
published using the new manual --historical-test option, preserving its source
and processing dates and suppressing notifications. Current revision:
cbcc995f5f42625352ed7be44542de5430a7b83036f2c595048bc987a0be313e.

The merge retains old X evidence for authors still present in the new release;
matching IDs take the incoming value. The 25% drop guard remains enabled.
A one-snapshot local cache is checked against every server manifest hash before
use; it avoids repeated large transfers over the database pooler. Independent
verification compares every stored JSONB page and the total page count to the
expected snapshot, followed by a fresh active-pointer check. No RLS/DDL changes.
See content-delivery.md for the local three-hour schedule and availability limits.
