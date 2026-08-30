# Hyperliquid Smart Money Live Runbook

> Legacy fallback and diagnostic runbook. Production uses Hyperdash as the
> primary Smart Money source with a 10-minute refresh interval; see
> `docs/operations/smart-money-live.md` for the active operating contract.

This runbook is the fallback operating contract for bSmart's read-only
Hyperliquid HIP-3 Smart Money path.

## Process topology

Production uses two independently restartable services:

1. **Smart Money ingest service**

   ```bash
   make smart-money-ingest-api
   ```

   It owns the source SQLite database, public trade WebSocket, wallet cursors,
   score materialization, atomic JSON collections, worker health JSON and the
   Realtime Read Model publisher. The publisher verifies every SHA/count and
   atomically replaces all Hyperliquid overlay collections in PostgreSQL. This
   removes cross-service filesystem sharing. The service supervises its worker
   and restarts unexpected exits with bounded exponential backoff.

2. **Client API**

   Run `services.client_api.main:create_app` with
   `BSMART_READ_MODEL_MODE=database` and the same Read Model database. The iOS
   app reads only this API; it never reaches the indexer or Hyperliquid.

Start the ingest service before the API. The last committed base release and
realtime overlay remain readable while ingestion restarts.

`make hyperliquid-smart-money-live` and
`make client-api-publish-live-smart-money` remain diagnostic CLI entry points
for isolated smoke tests and recovery. Do not run them alongside the production
ingest service against the same source database or producer partition.

## Persistent state

The ingest service requires a persistent volume containing:

- `/data/smart-money.db` plus its SQLite WAL/SHM while the process is live;
- `/data/client/` atomic materialized collections and manifest;
- `/data/health.json` and `/data/hyperliquidSmartMoney.json`.

Back up SQLite with the SQLite backup API or `make backup-db`; do not copy only
the main file while WAL writes are active. The Client API state database and
Read Model database are separate from this source database.

Restart is idempotent: trade identities, fill identities and immutable snapshot
keys de-duplicate replay; wallet fill cursors resume incremental history; the
manifest publisher ignores an already-applied content hash during its process
lifetime and database transactions keep every overlay generation coherent.

## Production defaults

- public trade capture: continuous WebSocket;
- score refresh: 30 seconds;
- Read Model publish: 60 seconds;
- historical candidate fills per enrichment batch: 4;
- low-latency active wallets per enrichment batch: 8;
- candidate universe: top 500 active in the last 30 days by observed notional,
  after crossing 5 observed trades or USD 10,000 observed notional;
- profile batch: 8, oldest eligible first;
- current account-state freshness: 5 minutes;
- market directory/subscription refresh: 60 minutes;
- score lookback: 30 days.

Client payloads are intentionally compact: only 1D/7D/30D metrics are
published, chart histories are downsampled to at most 90 points, and recent
trade/capital evidence is limited to the latest 30 days with bounded item
counts. Raw source tables remain auditable and are never sent wholesale to the
app.

The REST client paces itself below the official 1,200 weight/minute IP budget.
Never use `--no-api-pause` in production. Set `HYPERLIQUID_INFO_URL` or
`HYPERLIQUID_WS_URL` only for an approved endpoint. `HYPERLIQUID_WS_PROXY`
overrides automatic system proxy detection.

Active fills, historical fill catch-up and profile enrichment run in separate
background lanes. An account that reaches the 2,000-fill algorithmic exclusion
ceiling stops downloading additional history; it must not delay the public
trade tape, other candidate catch-up or minute-level publication.

## Health contract

The indexer atomically writes its configured health JSON. The service exposes
the combined view at `/health` and readiness at `/ready`.

Key fields:

- `status`: process transport state (`starting`, `healthy`, `degraded`,
  `stopped`);
- `readiness.realtime`: stream connected and latest Read Model within three
  publish intervals (minimum 180 seconds);
- `readiness.complete`: at least 95% available-history catch-up and at least
  95% profile coverage among currently qualified wallets;
- `readiness.ready`: both conditions;
- `readiness.reasons`: stable machine-readable failure/catch-up reasons;
- `stream.lastTradeAgeSeconds`, `stream.reconnectCount`, `stream.lastError`;
- `lastPublishAgeSeconds`;
- `coverage.candidateWallets`, `coverage.candidatePoolLimit`,
  `coverage.fillBackfillCoverage`, `coverage.observedFillBackfillCoverage`,
  `coverage.fullHistoryCoverage`, `coverage.historyLimitedWallets`,
  `coverage.policyLimitedWallets`, `coverage.sourceLimitedWallets`,
  `coverage.qualifiedProfileCoverage`;
- `activity.*WorkerBusy` and monotonically accumulated failures;
- `markets.lastRefreshAt` and market refresh failures;
- `collections`: counts committed in the latest client manifest.
- service-level `workerRestartCount`, `workerLastErrorAt`, `workerError` and
  `publisher.lastPublishedAt`/`publisher.lastError`.

Recommended alerts:

| Condition | Severity | Action |
|---|---:|---|
| `readiness.realtime=false` for 3 minutes | Critical | Check WebSocket, publisher and disk/database writes |
| `lastPublishAgeSeconds > 180` | Critical | Inspect enrichment errors, SQLite lock and materializer process |
| stream disconnected for 60 seconds or reconnect count rising continuously | Critical | Check endpoint/proxy/network; worker or service supervisor should reconnect automatically |
| `workerRestartCount` rises repeatedly | Critical | Inspect `workerError`, upstream availability, volume writes and process memory |
| fill/profile worker failure count increases | Warning | Inspect the latest worker error and API rate limits |
| `readiness.complete=false` for 24 hours after a cold start | Warning | Increase catch-up budget only after checking API headroom |
| `historyLimitedWallets > 0` | Informational | Expected official-source limit; those accounts are excluded from scoring |
| market refresh failure persists for 2 hours | Warning | Existing subscriptions remain active; investigate metadata API |

An illiquid market can legitimately have an old `lastTradeAt`; connection and
publish freshness, not a universal trade-age threshold, determine realtime
readiness.

## Coverage semantics

`fillBackfillCoverage` means the available official range was processed for the
current bounded top-500 high-activity candidate cohort.
`observedFillBackfillCoverage` reports the same status across every observed
counterparty for audit and is not a readiness gate.
`fullHistoryCoverage` excludes addresses that hit either bSmart's 2,000-fill
algorithmic policy ceiling or Hyperliquid's most-recent 10,000-fill source
ceiling. `policyLimitedWallets` and `sourceLimitedWallets` keep those reasons
separate. A limited wallet remains visible for audit but is classified as
algorithmic/truncated and cannot contribute to official asset direction.

Candidate selection is based on activity observed by bSmart after the durable
trade-tape checkpoint. Crossing the candidate threshold does not qualify an
account. Formal scoring additionally requires a complete available fill
history and the account minimums in `docs/contracts/smart_money.md`.

The public trade tape is complete only from the first durable live checkpoint.
It does not claim to enumerate every account that traded before deployment.

## Smoke verification

Use an isolated temporary database:

```bash
tmp="$(mktemp -d /tmp/bsmart-hl-smoke.XXXXXX)"
PYTHONPATH=. pipeline/.venv/bin/python -m pipeline.manage \
  hyperliquid-smart-money-live \
  --db "$tmp/live.db" \
  --output "$tmp/export.json" \
  --client-output-dir "$tmp/client" \
  --health-output "$tmp/health.json" \
  --refresh-seconds 2 --publish-seconds 2 \
  --candidate-backfill 1 --max-active-wallets 8 \
  --max-profile-wallets 2 --max-cycles 3
```

Verify:

1. running health reached `readiness.realtime=true` before bounded shutdown;
2. `activity.newTapeTrades` equals `SELECT COUNT(*) FROM hl_trade_tape` in a
   fresh smoke database;
3. no fill/profile worker failures occurred;
4. every collection hash/count matches `smart-money-live-manifest.json`;
5. one-shot publisher succeeds:

   ```bash
   BSMART_ENV=development BSMART_READ_MODEL_MODE=database \
   BSMART_READ_MODEL_DATABASE_URL="sqlite:///$tmp/read-model.db" \
     make client-api-publish-live-smart-money INPUT_DIR="$tmp/client" ONCE=1
   ```

## Incident recovery

- **Indexer restart:** allow the service supervisor to retry. Restart the
  service if retries continue. Cursors and immutable keys prevent duplicate
  facts; health remains not-ready until a fresh publish.
- **Corrupt/incomplete staging files:** remove only `.tmp` files. Keep the last
  committed manifest and collections; the next publish rewrites them.
- **Bad realtime overlay:** republish a retained previous committed manifest
  directory. The complete base Read Model remains separately versioned; do not
  edit active documents in place.
- **SQLite disk pressure:** stop the indexer cleanly, back up, then apply the
  repository retention policy. Never delete `hl_trade_tape`, `hl_fill`, wallet
  cursors or immutable snapshots as generic cache.
- **API rate limit:** keep pacing enabled and reduce candidate/profile batch
  sizes. Do not add parallel HTTP clients on the same IP to bypass the limit.

Official references:

- Hyperliquid Info endpoint: <https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint>
- WebSocket subscriptions: <https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions>
- Rate limits: <https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/rate-limits-and-user-limits>
