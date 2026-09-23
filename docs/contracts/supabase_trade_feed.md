# Supabase Trade Feed

## Trade theses, 2026-09-22 (pending rollout)

See `trade_thesis.md`. Native Feed now uses the viewer-aware social projection
for immutable trade theories, ownership actions and like state. The legacy RPC
remains available. Migration `202609220004_trade_theses.sql` must be applied
manually before Edge deployment. Published social trade theories can quote any
ranked author; plain trades retain the Top-25% rule. No production DDL/deployment
was executed for this change.

## Discovery rankings, 2026-09-22

`GET /bsmart-feed/rankings` accepts `kind=opinions|investors`,
`sort=traders|volume`, `window=1d|7d|30d|all`, and bounded `offset`/`limit`.
It requires the existing verified native account. The overview requests three
rows per kind; each More page requests twenty and retains independent filters.
Legacy `/popular` remains unchanged for older clients.

Only independently verified opening orders attributed to Top 25% social sources
are eligible. A window includes orders whose **last fill** is inside the range,
using existing verified order totals rather than invented per-fill history.
Opinion groups use opinion ID; investor groups use lowercase platform plus
author ID. Investor people counts deduplicate across that author's opinions;
each person's latest eligible direction determines the long/short split.
Every eligible order contributes its exact decimal notional once, including
repeat traders. If any amount is malformed, the group's amount is unknown;
the people ranking displays a dash and the volume ranking excludes that group.
This is attributed trading activity, not performance, follower count or ROI.

Ties use latest fill descending, then stable group ID ascending. The response's
`asOf` anchors subsequent pages to one time range; reconciliation can still
change historical aggregates, so clients deduplicate IDs while paginating.
Changing filters/account discards prior requests and pages. Unavailable
statistics never become zero or fixture data. No wallet/exchange calls are made.

Rollout: apply `202609220003_discovery_rankings.sql` in the iOS account project,
then deploy `bsmart-feed`. On 2026-09-22 the operator confirmed the migration
was applied; deployment succeeded and the management API reports version 14,
ACTIVE, updated 09:48:35 UTC. Anonymous endpoint probes failed with local
connection resets, so authenticated live ranking verification remains pending.
The RPC is executable only by service_role; account IDs and wallets are not
returned. Existing trading execution, public profiles and consent are unchanged.

## Historical source coverage and registration latency, 2026-09-22

The publisher now includes the trusted bundled representative-story chart nodes,
not only the truncated overview/evidence fixtures. The chart's summary remains a
summary: no original post text or actual purchase is inferred. Current published
author metadata takes priority; a source no longer in the current author list
retains its trusted bundled author snapshot. Previous catalog IDs are retained
before atomic activation so an existing App version does not lose attribution.
`feed-catalog-publish` includes the bundled plist by default; the explicit
`--representative-stories` path supports release-specific artifacts. Research
publication still needs this catalog publication step before new tradeable views
are exposed. Catalog publication is not a new daily research-data release.

Registration overlaps independent registry/idempotency reads, then source,
rate-limit and read-only exchange-status checks. Every result and the intent's
remaining lifetime must pass before insertion. No execution or retroactive
attribution is added. Immutable catalog items have a bounded 256-entry cache,
keyed by release and ID; the active release pointer still refreshes every 15s.
Missing objects return `opinion_unavailable` (422); storage failures stay 503.
The iOS order route decodes bounded registration error codes without changing
authentication, order-signing or unknown-submission recovery policy.

Deployment verification (2026-09-22): `bsmart-feed` deployed; the active private
catalog `order-attribution-repair-20260922` contains 2,780 objects, retaining 483
prior-only IDs. All 899 unique bundled chart nodes are present, and three
previously missing SNDK objects were read back and identity/ticker/rank checked.
The publisher/context suite passes 17 tests and Edge/schema suite passes 26.
Unauthenticated registration returns 401. The temporary credential-protected,
read-only diagnostic function was deleted and verified 404; it never signed,
registered or submitted an order. Real funded order latency is not measured.

## Subject totals, 2026-09-13

The authenticated `/subject-stats` endpoint sums distinct user/source pairs
across an author or Smart Money source. See `subject_trade_stats.md` for the
exact counting rule and operator migration. Private catalog money snapshots
reuse pre-submission registration and independent reconciliation; they have no
social percentile and do not enter the social opinion Feed/popular projection.

## Permanent public activity update, 2026-09-12

Native Feed no longer offers Demo or sharing settings. Migration
`202609120006_public_activity.sql` makes existing and future profiles public and
enforces both legacy visibility flags with a trigger, including old-client writes.
The compatibility `/sharing` API returns true/true and cannot modify profile identity.
Only existing platform public fields and independently verified executions are
published; Google email, auth identifiers and private keys remain excluded.
Account deletion still removes the profile. Public does not mean synthetic trades:
the existing verified-order and Top-25% eligibility rules remain unchanged.
This update is prepared locally; production migration and function rollout are pending.
The earlier consent-based rollout description below is historical, superseded by 006.

## Production rollout, 2026-09-12

Feed now runs independently inside the iOS Supabase account project. The operator
applied migrations 002 and 003; the Edge Function, private Storage catalog and
58 reviewed USDC equity/ETF market mappings were deployed. Vultr and the research
API are not runtime dependencies. The old research context route remains a legacy
adapter only. Catalog publication is a separate operator job, not client input.

Native Feed uses the same Supabase user and immutable wallet registration as live
trading. The legacy installation-token ledger remains backward compatible but is
not the source for signed-in native users. Production Feed has no Demo entry.

All `/functions/v1/bsmart-feed` requests use the verified Supabase user bearer and
publishable key, return JSON/no-store, and never accept an account ID as authority.

| Method/path | Purpose |
| --- | --- |
| GET `/` | Existing TradeFeedPage, offset/limit/profileId |
| GET `/profiles/{id}` | Existing FeedPublicProfile |
| GET `/profiles/{id}/portfolio` | Public Hyperliquid perps equity history, spot USDC and all open perp positions from this profile's server-registered wallet |
| GET/PUT `/sharing` | Deprecated compatibility route, permanently public; identity read-only |
| POST `/orders` | Immutable pre-submission opinion/author/ticker + cloid/coin/side/size/limit/nonce/expiry |
| POST `/sync` | Reconcile bounded pending orders belonging to authenticated wallet |
| GET `/opinions/{id}/traders` | Existing distinct-user OpinionTradersPage |
| GET `/popular` | Seven-day distinct-user opinion ranking, offset/limit |

Public portfolio reads resolve the public profile to its immutable wallet registration
on the server. The client cannot supply an address. Hyperliquid `perpDexs`,
`clearinghouseState` for every dex, `spotClearinghouseState`, and `portfolio`
are read in parallel after that mapping. Exchange failures are 503, not empty
positions or a zero balance; a profile without a registered wallet returns
`not_connected`. The visible equity curve uses exchange `perpDay` / `perpWeek` /
`perpMonth` account-value history, including its as-of time. Spot USDC is
listed separately: unified/portfolio margin can share that collateral, so the
client never sums it with perps equity into a fabricated total. Positions
include exchange-reported notional value, entry, unrealized PnL and ROI ratio.
No signing or trading capability is exposed by this endpoint.

Migration 004 adds `longTraders` and `shortTraders` to opinion-detail counts.
Their sum is `totalTraders`, including users without public profiles; one person
is assigned only their latest verified opening fill direction for this opinion.
The native proportional bar renders both counts, including zero/all-one-side
states; it is not a breakdown of just the currently loaded public trader page.
Migration `202609220001_opinion_trade_volume.sql` adds `totalNotionalUSD` to
the same response. It sums every verified fill's USD notional for the opinion,
including repeat orders and private traders; unlike the direction split it is
not deduplicated by person. If a historical fill has no valid notional, the
field is null rather than a misleading partial total. Older responses without
the field remain decodable and show no amount in the app.

`/popular` groups verified fills from the last seven days by opinion and user,
using that user's latest fill to determine direction. Opinions of Top 25% authors
are ordered by unique-user count descending, latest fill descending, then opinion
UUID. Response items contain opinion snapshots and the three counts only: no
private identities, wallet addresses, amounts, or execution IDs. Empty results
are distinct from service failures. The UI labels the seven-day window; entering
the detail shows all-time counts, so the totals may differ legitimately.
Migration 004 was manually applied and its RPCs verified on the account project;
the Edge Function includes the authenticated `/popular` route.
The 004 rollout passed 24 selected native unit tests, one simulator mode-switch
UI test and 32 Deno tests. Live RPC checks returned one real popular opinion and
confirmed both windowed and all-time direction totals; no synthetic fills were
inserted. This is a statistics/UI verification, not execution of a new real order.

Registration occurs before signing/submission. An attribution failure stops that
opinion-linked submission before it can send money; ordinary trading without an
opinion and reduce-only orders do not depend on Feed. Registration is not a fill.
No order, signature, wallet credential or fund transfer is created by the service.

The private Storage catalog resolves author/opinion evidence from reviewed real
project snapshots. All scored authors' opinions can be attributed; the public
Feed still selects Top 25% author snapshots. The Edge Function reads Storage with
its own service role; app clients cannot upload or change the catalog. An allowlisted
coin-to-ticker mapping is operator-configured; no string-guessing of instruments.

Primary exchange contract reference:
https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint

Hyperliquid `orderStatus` and `userFillsByTime` independently establish wallet,
cloid, coin, direction, original quantity, limit, order time and positive fills.
Terminal order and complete bounded fill response are required before publishing;
full 2,000-row windows fail closed. Decimal arithmetic uses exact integer scales.
Execution keys, not client receipt IDs, identify events. Rejected/resting/unknown,
testnet, deposits, reductions and historical pre-registration trades never count.
Client acknowledgement is only a sync trigger. Repeated sync does not resubmit.

Profiles are private by default. Nickname is explicitly submitted by the user;
canonical username, unique handle and avatar come from the account profile service.
The avatar may be a validated provider image or an explicitly uploaded private
JPEG served through a short-lived signed URL. Local photo files are not silently
uploaded. `bsmart-profile`, not `/sharing`, edits identity; see `account_profiles.md`. Amount sharing
requires identity sharing; withdrawal hides records immediately on server reads.
Public IDs are separate from auth IDs. No public wallet or private account ID.
Account switching clears UI data and invalidates in-flight responses.

Opinion-detail trader counts use the same native authenticated endpoint, never
the legacy installation ledger in production. Signed-out users see a login entry;
loading or service failure does not substitute demo people or invent a zero count.
Demo is opened explicitly and remains labeled. Real public rows show avatar,
username, handle and direction only; demo rows retain illustrative entry price and position
value. Neither displays leverage or execution time. Server timestamps remain for
verification, distinct-user aggregation and latest-fill ordering, not presentation.

SQL/Edge deployment and catalog publication are operator steps, not executed by
the app. See `supabase/ios-account/README.md`. Foreground Feed/order completion sync
and a Supabase pg_cron/pg_net worker share a leased queue (SKIP LOCKED, 120-second
claim lease). Each minute the worker checks up to five pending registrations;
device sync checks one owned order. Vault owns the scheduler secret; only its
digest comparison is exposed to service-role RPC. Client JWTs cannot run the worker.
Failed reads retry; unverified orders expire after seven days without inventing
fills. A private `worker-status.json` heartbeat and `make feed-service-check`
provide operational verification without exposing accounts or keys.

Scheduler authorization and queue claims retry transient gateway responses once
(400 ms delay). A lost claim response can leave a temporary lease, which expires;
it never means a verified fill. Permanent denials are not retried. Database
unavailability returns 503, not a misleading invalid-token 401. Diagnostic logs
contain response status/type, not tokens, wallet addresses or order contents.

`make feed-catalog-publish INPUT_DIR=... SOURCE_VERSION=... APPLY=1` publishes the
next real-data release. All objects upload before the active pointer changes;
the Edge cache checks that pointer every 15 seconds. Existing order snapshots
remain immutable. New opinions require a new catalog release to become eligible.

## Live Verification (2026-09-12)

- Supabase reports both Feed RPCs ready and cron active. Unauthenticated Feed and
  worker requests return 401 (the previous missing-function 404 is resolved).
- Private catalog publication contains 1,466 real opinions. Scheduled worker
  heartbeat was observed at a minute boundary; the readiness check returned true.
- There are currently zero registered/verified opinion trades. No fake accounts,
  ledger inserts or retrospective attributions were used to populate production.
- User-signed live order and provider-authenticated mobile end-to-end acceptance
  still require the user's own interaction; admin health checks do not replace it.
- Production observation found intermittent internal Supabase 504 responses;
  bounded RPC retry and durable lease recovery address transient failures, not
  an assumption of uninterrupted infrastructure availability.
- 31 Deno tests and 32 Python tests passed, including isolated PostgreSQL queue,
  privacy, distinct-user counts and Top 25% Feed projection checks. Hosted
  scheduler extensions were verified online, not emulated by the memory database.
- The final native regression run passed 43 selected XCTest cases covering order
  attribution, account isolation, Feed and opinion-trader models.

## Initial Local Verification (Before Deployment)

- Native simulator build and 51 selected XCTest cases passed: real account auth,
  account-switch/logout fences, order attribution before signing, rejection,
  ordinary/reduce-only orders and existing Feed behavior.
- 24 Supabase Deno tests passed, including 13 new Feed checks. Type checking passed.
- 28 Python context/Feed/ledger tests passed. YAML/local schema references,
  architecture boundaries, product terminology and whitespace checks passed.
- General `test_api.py` still has three fixture-dependent failures: it expects
  five portfolio signals while the current fixture provides one, and a digest
  test cannot find its expected old signal. These are not real trade Feed tests;
  all three reproduce with the new context router disabled. No fixture or source
  data was overwritten to make them pass.
- No production migration, deployment, authentication credential entry or actual
  monetary transaction was performed. SQL was reviewed and structurally tested,
  not executed against a live Supabase database. Deploy the backend before
  distributing the new attributed-order client; unavailable attribution stops
  opinion-linked orders before order signing/submission.
