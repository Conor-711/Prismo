# Equity Routing Operations

## EVM Infrastructure Track

The service-fusion development plan is
`docs/operations/xstocks-infrastructure-plan.md`. The new separate
`bsmart-equities` implements P1 discovery, P2 owner-bound previews and the P3 pre-execution ledger locally; `bsmart-markets` below
remains the older Solana research API. Neither enables funded execution.

EVM contract: `contracts/openapi/supabase-equities.yaml`; fixtures:
`contracts/fixtures/evm-equity-routing.json` and `evm-equity-preview.json`.
Endpoints are `GET /route?ticker=...` and read-only `POST /preview`.
The 50-name inventory is discovery scope, not execution approval. Live issuer
details and the full HL catalog override historical quote evidence.

From `supabase/ios-account`:

```bash
deno test --allow-read tests/equity_preview_test.ts tests/equities_test.ts tests/markets_test.ts tests/equity_screening_test.ts tests/equity_selection_test.ts tests/equity_shortlist_test.ts
deno check supabase/functions/bsmart-equities/index.ts scripts/smoke_equities.ts scripts/smoke_equity_preview.ts
deno run --allow-net=api.hyperliquid.xyz,api.xstocks.fi --allow-write=/tmp/equities-smoke.json scripts/smoke_equities.ts /tmp/equities-smoke.json
```

`BSMART_EQUITIES_DISCOVERY_ENABLED` defaults false. Its handler uses Auth `getUser`
and rejects anonymous/non-Apple/non-Google users before any provider read. Future
deployment uses `--no-verify-jwt` only with this handler validation, as with the
existing function. No credentials other than Supabase runtime Auth configuration
are needed in P1, no SDK signer is instantiated and no execution mutation route exists.
There has been no new production deployment, setting change or DDL in this phase.

Public metadata smoke is not an authenticated deployed HTTP test. Initial cold
directory loading observed an 8-second timeout followed by a ~38-second successful
load; warm identity discovery was much faster. The plan tracks verified snapshot
distribution/prewarming as a required production performance dependency. Never
remove full identity checks or return stale observations to hide that latency.
After bounded metadata-only GET retries, the final five-probe smoke passed:
NVDA retained HL; ASTS/SPY/JPM resolved Ethereum/Ink identities; OUST was excluded
from the inventory. Cold ASTS discovery still took ~28 seconds, warm SPY/JPM
~330/697ms. Local regression suite: 46 passed. Generated evidence is
`data/reports/xstocks/20261001/infra-smoke-bounded.json`.

### P2 Preview Configuration And Evidence

- `BSMART_EQUITIES_PREVIEW_ENABLED`: independent default-false read-only gate.
- `BSMART_EQUITIES_ETHEREUM_RPC_URL`, `BSMART_EQUITIES_INK_RPC_URL`: server-only
  HTTPS managed RPC endpoints for rollout. Do not print credentials in URLs.
  Development defaults use viem's public chain URLs. Ink's second official URL
  passed the probe; viem fallback tries the other URL for failed read queries only.
- CoW quote API is public; no direct xChange onboarding/key or new custody wallet.
  Owner must come from the existing authenticated account's `bsmart_wallets` row.

Dependencies are pinned and lockfile-backed. `nodeModulesDir=auto` avoids Deno's
cached npm resolution failure for cross-fetch/polyfill. Generated `node_modules`
is ignored. Test and type-check before bundling; no Edge deployment compatibility
or authenticated production HTTP acceptance is claimed by local checks.

Optional public smoke, from the same account project directory:

```bash
deno run --allow-net --allow-read --allow-write=/tmp/equity-preview.json scripts/smoke_equity_preview.ts --output /tmp/equity-preview.json
```

The script is fixed to a public synthetic address with **no signer or user
ownership**, ASTS, $100 USDC, 50bps slippage and a deliberately explicit 1000bps
network-cost ceiling for diagnostics, not a product default. Existing third-party
balances at that address are not our funding. It requests only quotes/RPC reads,
never approves, submits, transfers or substitutes an owned sell balance.

Initial smoke obtained Ethereum but rejected Ink RPC failure; recheck obtained
both validated candidates and no per-chain failure. Both are provider-unverified.
Evidence: `data/reports/xstocks/20261001/preview-smoke-recheck.json`. ~67-second cold
duration includes full metadata and provider reads, is not App-ready latency and
is not a bridge/fill estimate. Real account funded quote, owned sale, sponsorship,
fee-capped return, deployment and client rollout remain unverified/unimplemented.
Inspect explicit blockers; never infer readiness from HTTP 200 or verification.
Related regression suite: 60 passed. Function/project type checks and the public
preview response's OpenAPI schema validation passed. Whole-repo checks still
report nine existing iOS architecture violations and one existing resource
terminology violation, unchanged by this phase.

## P3 Ledger And Preloaded Catalog

User applied and database-verified on 2026-10-01:
`supabase/ios-account/supabase/migrations/202610010005_equity_intent_ledger.sql`
in the **iOS account project** `dzyitinagewdfkzjkuiz`, not the web project.
Do not rerun this non-idempotent migration or push all pending migrations from
the dirty worktree. It creates intents/legs, owner-read RLS and
service-only create/change/claim/observe RPCs, not a cron, key, signer, authorization
RPC or execution worker. The assistant executed no DDL.

`BSMART_EQUITIES_LEDGER_ENABLED` defaults false. Migrate and test before enabling
it separately from preview. Supported operations:

- `POST /intents`: `{clientIntentId, input: PreviewRequest}`.
- `GET /intents/{id}`: recover account's state/version/legs.
- `POST /intents/{id}/preview`: `{expectedVersion}`, recomputed from saved input.
- `POST /intents/{id}/cancel`: `{expectedVersion}`, pre-execution only.

Reused ID with other content returns 409; version conflict requires a recovery
read. Never change IDs after an unknown funded action to try again. Persistence
does not imply signing, fill, sponsorship or HL credit. Execution endpoints do
not exist, and no authorized legs are created by this phase. Service claim/observe
primitives and evidence hashes still need future verified provider/chain adapters.

For snapshots, the user creates private bucket `bsmart-equity-catalog`, file limit
4 MiB, MIME `application/json`, without authenticated/anonymous read/write policies.
Use service role only in the server/publisher, following existing
[Storage access control](https://supabase.com/docs/guides/storage/security/access-control).
The assistant did not create the bucket or execute DDL.

Prepare and validate locally without production writes:

```bash
cd /Users/windz7z/Desktop/crypto_us/supabase/ios-account
deno run --allow-net=api.xstocks.fi --allow-read --allow-write=/tmp/equity-catalog scripts/publish_equity_catalog.ts --output /tmp/equity-catalog
deno run --allow-read=/tmp/equity-catalog --allow-write=/tmp/equity-catalog-check.json scripts/smoke_equity_catalog.ts --directory /tmp/equity-catalog --output /tmp/equity-catalog-check.json
```

Explicit `--publish` additionally uses secret environment
`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`; grant environment and project-specific
network access deliberately. Never paste keys into commands/logs. The publisher
uploads immutable hash content, validates readback, then activates/verifies the
pointer. One publisher should run every five minutes on existing infrastructure
after rollout; **no schedule is installed**. Failed refresh never extends TTL.
Retention must keep active/recent objects; cleanup is not implemented here.

`BSMART_EQUITIES_CATALOG_SNAPSHOT_ENABLED` defaults false. Enable only with a
working private bucket, recent verified publication and monitored publisher.
Missing/stale/corrupt snapshots fail closed without user-time pagination fallback.
Keep live HL/detail/RPC checks. Local timings are not production Storage/App timings.

Public collection: 1,169 entries/995 USD identities, all 50 candidates present,
972,465-byte compact payload, about 23.4 seconds. Local file cold/warm readback
was about 33/3 ms, not remote Storage latency. Evidence:
`data/reports/xstocks/20261001/catalog-preload/active.json` and
`catalog-preload-check.json`. Dated files expire; do not deploy them as fresh later.
No production Storage upload, settings, cron, authenticated HTTP or funds test was performed.

The protected existing database connection is read through the content publication
configuration, never a web-project fallback. Use the client API virtualenv:

```bash
cd /Users/windz7z/Desktop/crypto_us
services/client_api/.venv/bin/python -m services.client_api.probe_equity_ledger
services/client_api/.venv/bin/python -m services.client_api.probe_equity_ledger --apply --output data/reports/xstocks/20261001/ledger-database-probe.json
services/client_api/.venv/bin/python -m pytest -q services/client_api/tests/test_equity_ledger_probe.py
```

Default mode checks schema/RLS/RPC privileges read-only. Explicit `--apply` creates
one controlled $1 draft for the existing test account, uses three independent
transactions to verify deduplication, rejects input/owner/account/version conflicts,
and verifies cancel retries. Synthetic SQL preview fixtures verify expiry/CAS/retry
guards only inside a rolled-back savepoint; they are not provider quotes. The probe
retains its own cancelled audit row, creates no legs and never signs/submits funds.
It tests database `authenticated` role isolation, not an actual App JWT/HTTP session.
On 2026-10-01 these checks passed; evidence is `ledger-database-probe.json`.
Future leg workers, real authorization, receipt/CoW UID reconciliation and
production Storage/HTTP acceptance remain pending.

```bash
deno test --allow-read tests/equity_intents_test.ts tests/equity_catalog_snapshot_test.ts tests/equity_ledger_database_test.ts tests/equity_preview_test.ts tests/equities_test.ts tests/markets_test.ts tests/equity_screening_test.ts tests/equity_selection_test.ts tests/equity_shortlist_test.ts
deno task check
deno check scripts/publish_equity_catalog.ts scripts/smoke_equity_catalog.ts
```

79 related Deno tests passed, including three source-level SQL guards; the probe
has five Python unit tests. Cloud pre-execution transaction/RLS-role checks passed;
execution-leg and production Storage/HTTP acceptance remain pending. Global checks
retain nine existing iOS boundary and one existing resource terminology issue.

## P4 Funding Preflight (Local Only)

`POST /intents/{id}/funding-preview` accepts `{expectedVersion}` only and needs a
fresh quoted intent, not a draft. Enable the separate default-false
`BSMART_EQUITIES_FUNDING_PREVIEW_ENABLED` only after preview/ledger dependencies
work. It shares the configured execution-chain RPCs and existing server-only
`BSMART_RELAY_API_KEY`; public smoke does not use a key. No new signer, provider
account, issuer KYB integration, DDL, cron or production setting was installed.

Modules: `funding_types.ts`, `hypercore_funds.ts`, `funding_guard.ts`,
`relay_funding.ts`, `funding_preview.ts`. Contract v0.4.0 and
`contracts/fixtures/evm-equity-funding.json` record the non-executable boundary.
Do not feed returned plan amounts into an existing withdrawal executor. There
is no authorization token/lease, reserved balance or installed executable leg.

```bash
deno test --allow-read tests/equity_funding_test.ts
deno check supabase/functions/bsmart-equities/index.ts scripts/smoke_equity_funding.ts
deno run --allow-net=api.relay.link --allow-write=/tmp/equity-funding.json scripts/smoke_equity_funding.ts --output /tmp/equity-funding.json
```

The smoke requests four unsigned $100 quotes, HC perps to Ethereum/Ink and the
reverse direction, using the address in Relay's public documentation. We do not
own that address, infer its balance or instantiate a signer. Only safe normalized
route/fee/step summaries are saved. This is not an authenticated HTTP, funded
route, sponsorship, fill or HL-credit test. Requests do not register reusable
deposit addresses, submit permits, authorize nonces or send funds.

All plans retain execution, reservation and gas blockers. Native-gas routes are
diagnostic only and rejected by the planner; a permit-shaped quote retains
`permit_executor_unverified` and requires P5 deployment/typed-message validation.
The runtime makes no endpoint capable of executing the quote. Across's existing
withdrawal service remains unchanged and is not a general-purpose fallback.

On 2026-10-01, the recheck's two HC-origin public requests were unavailable;
Ethereum return validated a permit-shaped $100 quote with minimum HL receipt
$99.843955 (~$0.156045 quoted loss), while Ink returned $99.829999 (~$0.170001)
with ordinary EVM transaction steps/native-gas requirement. These are momentary
unfunded quotes, not stable fee estimates, success rates or proven gasless fills.
The Ink plan is blocked. Ethereum remains blocked on executor/signature validation,
authorization, reservations and real credit proof. See
`data/reports/xstocks/20261001/funding-smoke-recheck.json`; the earlier report
recorded the incorrect depository-versus-router assumption, now corrected.
21 new and 79 existing related Deno tests passed; project type checks passed.
OpenAPI request, usable/unavailable fixtures and both safe live quote projections
passed schema validation. Whole-repo architecture/terminology checks still report
the same nine existing iOS boundary violations and one resource metric term;
this phase changed no iOS files or those existing failures.

Remaining P4/P5 dependencies: provider route/permission funded acceptance,
atomic wallet-wide reservation (the read guard is not a lock), authorized leg
installation, provider/chain/HL proof, return quote refresh after actual sale,
nonce-safe signing and known-ID-only reconciliation. Existing in-flight statuses
block instead of being interpreted as fresh balances. Failed return must retain
identifiable execution-chain USDC; never show a hypothetical HL balance.

## Legacy Solana Scope

`bsmart-markets` is a separate read-only Edge Function in the iOS account project
`dzyitinagewdfkzjkuiz`. It does not replace the existing Hyperliquid execution,
wallet registration, funding, withdrawal or position reconciliation adapters.
There is no database migration, custody key, order submission or gas sponsor.
The iOS buy action is not connected in this phase.

Contract: `docs/contracts/equity_routing.md` and
`contracts/openapi/supabase-markets.yaml`; sample responses in
`contracts/fixtures/equity-routing.json` are fixtures, not live market evidence.

## Configuration

- Existing Supabase runtime provides `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.
- `BSMART_JUPITER_API_KEY`: server-only Jupiter credential; never put in the App,
  query string, a committed file or logs.
- `BSMART_XSTOCKS_PREVIEW_ENABLED`: defaults false. `true` enables indicative
  read-only buy previews only. No setting in this module enables execution.

Route discovery uses public HL and issuer metadata, not the authenticated xChange
mint/redemption service. Read-only Jupiter previews omit both `taker` and `payer`;
they are not evidence that the user's balance is sufficient or gas is sponsored.
The current output is raw token units, not stock shares (Scaled UI remains separate).

## Validation And Deployment

From `supabase/ios-account`:

```bash
deno test --allow-read tests/markets_test.ts
deno check supabase/functions/bsmart-markets/index.ts
supabase functions deploy bsmart-markets --project-ref dzyitinagewdfkzjkuiz --no-verify-jwt
```

Gateway verification is disabled only because the handler verifies each JWT with
Supabase Auth `getUser`, rejects anonymous users and requires Apple/Google identity.
No service key is ever returned. Unauthenticated route requests must return 401
without reaching market providers. Valid authenticated `/route?ticker=AAPL`
should preserve the raw current HL identity when listed; `/route?ticker=AEHR`
must first verify the complete HL catalog. Test accounts use their own real JWT,
not service role impersonation. Never paste test tokens into logs or this runbook.

Preview remains 503 `preview_disabled` unless both the server gate and credential
are present. Quotes on an HL-listed asset return 409 `xstocks_route_required`;
do not turn quote errors, provider outages or halted markets into venue fallback.
HL metadata and selected issuer asset status must be less than 30 seconds old.
The complete paginated issuer identity registry is cached for at most ten minutes;
a cold load can take substantially longer than an HL-only read. Asset detail is
re-read and identity matched, and an expired HL observation is refreshed before
returning xStocks. Never use this cold path as a signing-time validation shortcut.
Retry is a new
read, never automatic submission. There is no executable transaction in responses.

Deployment status must be reported separately from local tests. Successful public
registry reads or function deployment do not constitute funded trading acceptance.

## Execution Work Remaining

1. Link an independent user-owned Solana wallet to the same account with ownership
   proof. Keep the funded EVM wallet untouched and positions bound to their venue.
2. Integrate native Solana signing and decoded instruction/account validation,
   exact input, minimum output, expiry and official issuer mint/program allowlists.
3. Add a durable order intent/receipt journal and reconcile ambiguous submissions
   on chain without duplicate retries. Prepare DDL for user execution if needed.
4. Resolve native Solana USDC funding, bridge failure/refund handling and app-funded
   gas sponsorship. A hidden bridge still exists operationally; never spend HL
   collateral as if it were already Solana USDC or double-count funds in transit.
5. Preserve the user's amount/slippage/USDC fee authorization, issuer lifecycle and
   provider eligibility. Test a bounded real order with the user performing the
   consequential financial action before enabling general availability.

These are prerequisites for seamless trading, not optional UI refinements.

## P5a CoW Codec And Reconciliation

Local modules only, not deployed or wired into execution HTTP/cron. No migration
or user action is needed for this batch; do not rerun the existing ledger DDL.
All existing kill switches remain off. No wallet locks, authorized legs, signing,
order submission, bridge transfers, gas sponsorship or HL credit have been added.

The server's private canonical quote material and SDK-generated preparation must
not be exposed in the current preview API or trusted when supplied by a client.
`verifyCowSignature` proves only EOA signing; future workers must use fresh server
wallet/intent/chain context with `verifyBoundCowSignature`, recheck live routing,
and commit authorization/reservation atomically before any one-shot submission.
The no-signer official adapter uses offline-only transport for SDK cryptography;
it is not the app's Privy signer. Never enable the SDK's eth_sign fallback.

Read-only `cowStatusReader/cowReceiptReader/reconcileCowOrder` require original
private prepared data, exact UID and the chain's finalized/canonical receipt.
Missing finalized support or unavailable RPC fails closed. Configure stable
managed HTTPS RPCs for funded rollout; public defaults are development probes.
The recovery worker is not deployed and no leg/parent transition occurs yet.
Concurrent batches with ambiguous net owner transfers are held, not attributed
to this order. An API cancelled/expired/404 is not a fund-release decision.

`confirmed` means the synthetic/local evidence validator can verify received
tokens, not that the return has started. Sale credit evidence excludes existing
wallet balance; reread currently spendable USDC before a fresh return quote and
authorization. Return/gas/HL credit remain independent. Finalized confirmation
may wait longer than the visible CoW fill; measure both during future real tests.

From `supabase/ios-account`:

```bash
deno test --allow-read tests/equity_cow_order_test.ts tests/equity_cow_reconciliation_test.ts tests/equity_preview_test.ts
deno check supabase/functions/bsmart-equities/cow_order.ts supabase/functions/bsmart-equities/cow_status.ts supabase/functions/bsmart-equities/cow_receipt.ts
```

`contracts/fixtures/evm-equity-cow-codec.json` is a deterministic, synthetic SDK
vector and fabricated receipt evidence; it is not a provider quote, live trade
or blockchain transaction. No production key is read by these tests.

## P5b Private Preparation Rollout

Local implementation only. New migration is prepared, not applied by the agent:
`supabase/ios-account/supabase/migrations/202610010006_equity_preparations.sql`.
Run it once in the iOS account project `dzyitinagewdfkzjkuiz`, after the already
applied `202610010005`; do not rerun earlier migrations or use the web project.
No user-facing trade capability is activated by the migration.

The user applied this migration on 2026-10-01. Do not rerun it. Cloud private
grants, protected RPCs and all five triggers passed the read-only probe. Two
READ ONLY connections using a synthetic unbound owner verified the old withdrawal
key, reentrance, fail-closed contention and release at transaction end. No user
records were written. Evidence: `data/reports/xstocks/20261001/preparation-database-probe.json`.
P5c subsequently passed rollback-only multi-connection write-RPC acceptance;
real JWT/HTTP remains untested. See the P5c section below.

Keep `BSMART_EQUITIES_PREPARATION_ENABLED=false` until migration permissions,
shared withdrawal guards, multi-session contention and authenticated HTTP are
accepted. This gate depends on enabled preview/ledger, but does not enable signing
or submission. Current APIs return no signing material. Prepared private data and
future signatures must not be logged or placed in public content Storage.

The migration affects legacy withdrawal updates as well as new preparations.
Before applying, inventory active withdrawals and authorized equity intents; do
not reclassify uncertain records as terminal. Existing legacy `accepted` and
`core_debited` records are conservatively held by the shared guard, matching P4;
their release needs a verified reconciliation policy before legacy rollout.
The 2026-10-01 pre-migration read-only audit found no rows in either withdrawal
table, no equity legs, and only two cancelled equity drafts. This dated audit is
not a future release approval or proof that no external wallet activity exists.

After the user applies DDL, use the read-only probe from the repository root:

```bash
services/client_api/.venv/bin/python -m services.client_api.probe_equity_ledger --preparations
```

It checks exact project identity, private table/column grants, protected RPCs,
five enabled triggers and two-connection shared-lock contention; it never fetches
signing payloads/signatures or writes rows. `--apply --preparations` is rejected.
Do not expose server database secrets.
Concurrent write-RPC/race acceptance and real JWT/HTTP remain separate tests,
not proved by the read-only lock probe or PGlite.

From `supabase/ios-account`, local tests execute SQL only in isolated in-memory
PGlite; no hosted DDL or real account creation occurs:

```bash
deno test --allow-read tests/equity_preparations_test.ts tests/equity_preparation_database_test.ts
```

Preparation idempotency returns the same record after a lost response; expiry
does not release the wallet. A reserved preparation can be cancelled via the
existing CAS cancel RPC, even after wallet problems. Authorized records cannot be
cancelled, expired away or claimed for execution in this stage. Do not send real
signatures into internal authorization while execution/recovery remains closed.

## P5c Exposure And Native Codec

The user applied `202610010007_equity_signing_exposure.sql` in the iOS project
on 2026-10-01. Do not rerun 005/006/007. Protected signing-start RPC grants,
private columns and signing-aware wallet/parent guards passed the cloud read-only
check. No signing HTTP route exists and no real wallet is invoked.

```bash
services/client_api/.venv/bin/python -m services.client_api.probe_equity_ledger --preparations --signing-exposure
```

Evidence: `data/reports/xstocks/20261001/signing-exposure-database-probe.json`.
The independent concurrent probe requires explicit `--rollback-writes`. It seeds
two synthetic SQL-boundary drafts for an existing bound account in uncommitted
admin transactions, then changes to service_role for preparation RPCs. This avoids
the create RPC's separate account-idempotency lock masking the wallet race.
One preparation holds the legacy wallet key; a second fails closed and its nested
quote/version rolls back. Both old reserve RPCs hit the same lock and fail with a
bounded lock timeout, never accept a withdrawal. Rolling back the holder permits
the second preparation, immutable retry and (with 007) signing-start retry plus
blocked cancellation. All test rows in all five tables are checked absent afterward.

```bash
services/client_api/.venv/bin/python -m services.client_api.probe_equity_preparations --rollback-writes --signing-exposure --output data/reports/xstocks/20261001/signing-exposure-concurrent-write-probe.json
```

This briefly takes a real coordinated wallet lock, so run only in a controlled
quiet window. The synthetic order/material are deliberately not crypto/provider
evidence; no signature, authorization, leg, provider order or transfer is created.
The probe performs no DDL or user-account creation and commits no test rows.
Its dated success is not a real funded race, App JWT/HTTP or external-wallet lock.

`beginPreparedSigning` is internal-only and persists exposure before returning
any order. The current prepare endpoint still returns only a safe summary. Neither
timer expiry nor wallet rejection can release a signing reservation; recovery
must query the original UID, never create/sign another order automatically.
SQL can enforce CAS/state but cannot verify EIP-712; service verification remains
mandatory. Execution-closed trigger, sponsor and funding/return gates remain intact.

From `supabase/ios-account`, reproduce public offline native vectors:

```bash
deno run --allow-read --allow-write=../../contracts/fixtures/evm-equity-signing.json scripts/equity_signing_vector.ts
deno test --allow-read tests/equity_preparations_test.ts tests/equity_preparation_database_test.ts
```

The Swift codec uses the existing pinned WalletCore/BigInt, has no signer or
networking, rejects arbitrary order/domain/extensions and validates original
reviewed intent/asset/amounts. Fixtures cover both execution chains and uint256
above UInt64; disposable public test key 1 is not a production wallet.
Run `make ios-build` and `IOS_TEST_ONLY=BSmartTests/EquityCowOrderCodecTests make ios-test`.
API deployment, wallet wiring and bounded funding/return consent remain separate.
Only a later reviewed migration may replace the database execution guard.

Next: finish iOS dedicated signing codec and bounded funding/return consent;
then one-shot CoW submission, evidence CAS and owner-visible reconciliation.
Production catalog snapshot/HTTP and sponsor/funded bridge acceptance are still
required before activating any real transaction.
Before exposing typed data to the wallet, add a persisted signing-start/exposure
state. A payload already handed to a signer cannot keep using the current unsigned
cancel-and-release path. Do not enable signing merely by changing an HTTP flag.

## EVM Candidate Screening

Current dated shortlist and evidence interpretation:
`docs/operations/xstocks-v1-candidates.md`.

The target is now 30-50 assets. `scripts/select_xstocks_candidates.ts` ranks only
official USD-underlying identities absent from the full current HL catalog. The
one-year X counts are a product-audience popularity proxy, not exchange volume;
`data/reports/xstocks/20261001/popularity.json` contains aggregates only, no handles
or post text. The immutable read-only committed database view may omit live WAL
rows; do not use it to claim real-time or global popularity.

```bash
deno test tests/equity_selection_test.ts tests/equity_screening_test.ts tests/equity_shortlist_test.ts
deno run --allow-read=../../data/reports/xstocks/20261001/expanded-registry.json,../../data/reports/xstocks/20261001/popularity.json --allow-net=api.hyperliquid.xyz --allow-write=/tmp/xstocks-top50.json scripts/select_xstocks_candidates.ts --registry ../../data/reports/xstocks/20261001/expanded-registry.json --popularity ../../data/reports/xstocks/20261001/popularity.json --limit 50 --output /tmp/xstocks-top50.json
```

Inputs expire after 24 hours and must be re-collected. A complete registry is
obtained from `/api/v2/public/assets` by checking every `currentPage` and
`hasNextPage`, without filtering to known ticker guesses or considering a partial
load complete. The recorded public snapshot has 1,169 assets; that number includes
non-USD instruments, HL-listed instruments and assets without usable quotes.
Selected quote probes independently reread the official asset details and HL.

The expanded 75-name probe produced a 50-name draft, with 12 additional qualified
candidates and separate missing-quote/high-cost reserves. Finalization requires
an observed $1,000 pair; a 3% research difference screen is advisory, not an
execution fee cap. AMC/FLY still lack $100 pairs. Regenerate from fresh reports:

```bash
deno run --allow-read=../../data/reports/xstocks/20261001 --allow-write=/tmp/xstocks-shortlist.json --allow-net=api.hyperliquid.xyz scripts/finalize_xstocks_shortlist.ts ../../data/reports/xstocks/20261001/expanded-selection.json ../../data/reports/xstocks/20261001/expanded-quotes.json ../../data/reports/xstocks/20261001/expanded-ink-quotes.json /tmp/xstocks-shortlist.json
```

The finalizer matches issuer and token identities, keeps failed size tiers
separate, preserves `executionEnabled=false`, and checks the full live HL catalog.
It does not select an executable route from asynchronous historical quotes.

The preferred V1 investigation now uses public CoW EVM quotes rather than direct
issuer onboarding. This does not change the existing Solana Edge Function.
Sell proceeds default to HL perps after verified return funding; return transfers
and App execution remain unimplemented. Weekend depth is a soft selection factor;
never sacrifice price protection or label missing weekend samples as successful.

From `supabase/ios-account`, run the unsigned research tool with a narrow output
permission (create the parent directory first):

```bash
deno test --allow-read tests/equity_screening_test.ts
deno run --allow-net=api.hyperliquid.xyz,api.xstocks.fi,api.cow.fi --allow-write=/tmp/xstocks-screening.json scripts/screen_xstocks.ts --amounts 100,1000 --networks Ethereum --output /tmp/xstocks-screening.json
```

The default candidate list is editorial, not a measured popularity ranking.
Use `--tickers OUST,ALAB,AEHR`, `--networks Ethereum,Ink,Arbitrum`,
`--quality optimal` and `--variants all` for focused validation of raw tokens and
current official V2 wrappers. A synthetic address is used only for quotes, never
signing or submission. Keep `verified=false` exactly as returned. Successful
HTTP responses and fee-inclusive quote roundtrips do not prove execution,
allowance, gas sponsorship or future weekend liquidity. Repeat observations under
different market conditions; no recurring job or live trading flag is enabled.
