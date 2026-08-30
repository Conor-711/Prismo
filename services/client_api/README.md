# bSmart Client API

This service owns the versioned `/v1` boundary consumed by the native iOS app.
It is separate from the static Web client and from ingestion/pipeline jobs.

Current development scope:

- anonymous installation sessions with hashed opaque tokens;
- idempotent manual portfolio state;
- signal read/save/ignore/feedback state;
- notification preferences and APNs device registration;
- versioned materialized read models for production-shaped reads;
- instant and daily-digest notification planning, immutable digest snapshots, and APNs delivery;
- authenticated Mr Collie questions grounded in portfolio, Smart Account, and Smart Money evidence;
- privacy-minimized, installation-scoped product telemetry with bounded retention.

Fixture mode is development-only. `BSMART_ENV=production` refuses to start with
`BSMART_READ_MODEL_MODE=fixture`. Database mode reads versioned JSON documents
from `client_read_model_document`; a separate publisher owns those documents
and the API never imports or invokes pipeline jobs.

## Run locally

```bash
make client-api-install
make client-api-dev
```

To exercise the database-backed production shape with current mock contracts:

```bash
make client-api-seed-mock
BSMART_ENV=development BSMART_READ_MODEL_MODE=database make client-api-dev
```

`client-api-seed-mock` is idempotent and intended only for development. The
production publisher will materialize validated Smart Account, Smart Money,
relationship, and ticker intelligence objects into the same collection model.

## Mr Collie

Mr Collie is an authenticated Client API capability, not a direct iOS-to-model
integration. The server builds a bounded context from the installation's
portfolio and the active versioned read models, calls DeepSeek, and only returns
citations whose IDs exist in that context. The DeepSeek key therefore belongs
only in the Client API environment:

```bash
DEEPSEEK_API_KEY=...
DEEPSEEK_BASE_URL=https://api.deepseek.com
BSMART_MR_COLLIE_MODEL=deepseek-v4-flash
BSMART_MR_COLLIE_TIMEOUT_SECONDS=45
BSMART_MR_COLLIE_REQUESTS_PER_MINUTE=8
```

Local development automatically reads the uncommitted repository `.env`
without replacing variables already exported by the shell. Production must
provide these values through the hosting secret manager. When DeepSeek is not
configured or cannot return valid grounded JSON, the API fails closed and iOS
clearly falls back to its deterministic on-device evidence view.

Mr Collie defaults to `deepseek-v4-flash`: its bounded evidence explanation is
a short structured-output task and does not require the Pro model by default.
Other pipeline workloads may keep their own Pro setting; changing Mr Collie
does not change those jobs.

For the isolated Mock Internal Alpha, use dedicated state and read-model
databases instead of the normal development files:

```bash
make client-api-alpha-seed
make client-api-alpha-dev
```

This serves the contract fixtures through the production-shaped database path
on port `8082`. It never reads the production database and must be deployed on
an HTTPS-only alpha hostname before a real-device or TestFlight build uses it.
Do not point `bSmart Internal Alpha` at `https://api.bsmart.today`.

With the local server running, verify installation authentication, portfolio
state, read-model counts, stable cache headers and the immutable daily brief:

```bash
make client-api-alpha-smoke
```

## Deploy Mock Internal Alpha

The Alpha service has a dedicated container that preserves the database-backed
runtime shape while seeding only the versioned mock contracts:

```bash
make client-api-alpha-image
docker run --rm -p 8082:8080 \
  -v bsmart-alpha-data:/data \
  bsmart-client-api-alpha
```

Deploy with repository root as the build context and
`services/client_api/Dockerfile.alpha` as the Dockerfile. Mount a persistent
volume at `/data`, expose container port `8080`, and configure the platform
health check to use `/health`. The image runs as a non-root user, refuses
fixture read mode, materializes the current mock release idempotently on boot,
and keeps installation, portfolio, follow and telemetry state in the separate
state database. TLS must terminate at the hosting platform so the public origin
is `https://mock-api.bsmart.today`.

The required environment is documented in `alpha.env.example`; do not change
`BSMART_ENV` to production or point this image at production storage.

## Read model publishing

A production materialization run must first write all eight contract
collections to one directory. Publish the complete snapshot only after upstream
validation succeeds:

```bash
make client-api-publish-read-models \
  INPUT_DIR=/path/to/validated/read-model \
  SOURCE_VERSION=pipeline-2026-08-04T16:00Z
```

Publishing is content-addressed and immutable. All documents are inserted under
one release ID before a single active pointer changes, so API readers never see
a partial batch. Repeating identical content is idempotent; previous releases
remain available for an explicit rollback. Main read endpoints return a stable
private `ETag` for their active collection.

Smart Money uses a narrower continuous overlay after the complete base release
exists:

```bash
BSMART_READ_MODEL_DATABASE_URL='postgresql+psycopg://...' \
  make client-api-publish-live-smart-money \
  INPUT_DIR=data/runtime/smart-money-live
```

The publisher reads `smart-money-live-manifest.json` twice, verifies every
collection SHA-256 and count, and atomically replaces the realtime overlay for
`smart-money`, `smart-money-movements`, `smart-money-evidence` and, when present, `portfolio-signals`
plus `ticker-intelligence` in one transaction. It never exposes a mixed
generation, while the complete base release remains separately versioned. Upstream process
ordering, health SLOs and recovery are documented in
`docs/operations/smart-money-live.md`.

## Notification planning

```bash
make client-api-plan-notifications
make client-api-plan-digests
```

The planner creates at most one delivery per installation and signal. Only
current `critical` or `important` signals for a held or watched ticker enter the
instant queue. It applies instant-alert, muted-ticker, and quiet-hours settings;
it also enforces a six-hour per-ticker cooldown and an eight-alert rolling
24-hour installation cap. Lower-priority, delayed, or rate-limited signals are
recorded as skipped for auditability. The
digest planner creates at most one portfolio brief per installation and local
calendar day, after the user's selected time. It includes only current changes
from the preceding 24 hours for held or watched, non-muted tickers. The planner
stores the full selected signal documents before queueing the notification, so
`GET /v1/daily-digest`, the push body and later offline reads retain the same
evidence even after active read models change.

Planning does not send APNs traffic. The delivery worker claims due rows, sends
over Apple's HTTP/2 provider API, retries transient failures, records every
attempt, and removes device tokens rejected as invalid by APNs. Production
workers claim rows with a lease and database `SKIP LOCKED` semantics:

```bash
export BSMART_APNS_TEAM_ID=YOUR_TEAM_ID
export BSMART_APNS_KEY_ID=YOUR_KEY_ID
export BSMART_APNS_TOPIC=today.bsmart.ios
export BSMART_APNS_PRIVATE_KEY_PATH=/secure/path/AuthKey_KEY_ID.p8
make client-api-dispatch-notifications
```

Hosted environments may set the PEM directly through `BSMART_APNS_PRIVATE_KEY`
instead of mounting a file. Run `python -m services.client_api.notification_worker`
for continuous delivery; it polls the durable queue every 30 seconds by default.
Production image and Railway service configs are available at
`services/client_api/Dockerfile`, `services/client_api/railway.api.json`, and
`services/client_api/railway.notifications.json`.

Run the two planners on a schedule before the dispatcher. The `.p8` signing key
is release infrastructure and must never be committed. Without real Apple
credentials the dispatcher intentionally fails closed rather than simulating a
successful production push.

Then launch the iOS Debug scheme with:

```text
--use-live-api
BSMART_API_BASE_URL=http://127.0.0.1:8081
```

## Test

```bash
make client-api-test
```

The authoritative public contract remains
`contracts/openapi/bsmart-v1.yaml`. FastAPI's generated schema is operational
documentation and must not replace contract-first changes.

## Telemetry boundary

`POST /v1/telemetry/events` accepts only enumerated interactions and structured
IDs. The iOS durable outbox records Push, daily brief, signal and source-evidence
opens plus save, ignore and feedback actions. It never sends post text, source
URLs, search text, cost basis, shares or portfolio weight. Event IDs make retries
idempotent; the default server retention is 90 days and can be reduced with
`BSMART_TELEMETRY_RETENTION_DAYS`.
