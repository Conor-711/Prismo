# X Smart Account Realtime Operations

## Scope

The service monitors the formal X Smart Account top quartile. The current ranking is refreshed once per day; new posts only attach the latest published Score snapshot. Stable numeric X user IDs identify authors, while handles remain mutable display fields.

`BSMART_X_POOL_LIMIT=0` means "use the complete top quartile", not "monitor every ranked author". For example, a formal population of 137 authors produces 35 active subscriptions. A positive pool limit is only a canary cap inside that quartile.

Keep `BSMART_X_RECONCILE_MAX_PAGES=40` for the formal top-quartile pool. The provider returns at most 20 posts per time window, so high-volume rules need enough split requests to complete the 15-minute compensation pass.

The data path is:

```text
TwitterAPI.io rules -> webhook/WebSocket -> x_realtime_post
                                        -> 15-minute bounded-window reconciliation
                                        -> Call extraction + complete zh/en translation
                                        -> x_realtime_call (ready)
                                        -> smart-account-updates + account_leads
                                        -> Client API -> holding/watchlist notification planner
```

Pure retweets are excluded. Original posts, replies, and quote posts are accepted, but only author-owned actionable evidence can pass the X Call policy.

## Production setup

1. Run `make x-ingest-bootstrap POOL_LIMIT=10`. It applies the additive realtime/ranking schema, publishes the current formal X ranking from `data/dev.db`, initializes Client API state/read-model tables, and selects the canary pool.
2. Use PostgreSQL for all runtime stores. A single `DATABASE_URL` is sufficient when the ingestion, Client API state, and read models share a database; explicit `BSMART_X_DATABASE_URL`, `BSMART_READ_MODEL_DATABASE_URL`, and `BSMART_CLIENT_API_DATABASE_URL` values override it.
3. Set the provider webhook URL to `https://<host>/webhooks/twitterapi-io/<BSMART_X_WEBHOOK_TOKEN>`.
4. Deploy the same image as two processes:

```bash
python -m uvicorn services.x_ingest.main:create_app --factory --host 0.0.0.0 --port 8080
python -m services.x_ingest.worker
```

Railway service configs are provided at `services/x_ingest/railway.api.json` and
`services/x_ingest/railway.worker.json`. The API owns the public callback; the worker must not
expose a public port.

5. Deploy the production Client API with `services/client_api/railway.api.json`. It reads the same PostgreSQL read-model and state tables used by the X worker.

6. Run the APNs dispatcher continuously with `services/client_api/railway.notifications.json`. The X worker plans holding/watchlist notifications but deliberately does not send APNs inside the ingestion transaction:

```bash
python -m services.client_api.notification_worker
```

The worker accepts either `BSMART_APNS_PRIVATE_KEY_PATH` or a PEM value in
`BSMART_APNS_PRIVATE_KEY`; never commit the signing key.

7. Start with `BSMART_X_POOL_LIMIT=10`. Keep the canary running for 24 hours, run the completeness audit, then set the value to `0` and restart the worker.

## Fully local operation

TwitterAPI.io custom filter rules can deliver the same `tweet` events over one authenticated
outbound WebSocket connection. This is the preferred local transport because it does not require a
public webhook URL:

```bash
# Copy the provider API key to the macOS clipboard without pasting it into the terminal.
make x-local-config
make x-local-up
make x-local-status
```

The local worker enables `BSMART_X_STREAM_ENABLED=true`, keeps one provider connection open, and
continues to run the 15-minute REST reconciliation. The webhook endpoint remains available on
`127.0.0.1:8083` for payload tests, but it is not exposed publicly. `make x-local-down` is the
explicit emergency stop. Docker's `restart: unless-stopped` restarts crashed processes and restores
them after Docker Desktop restarts.

Always use `make x-local-down` for a planned local stop. It first deactivates the provider rules
recorded in local PostgreSQL and only then stops the containers, preventing matched-post charges
while the consumer is offline. The next `make x-local-up` reactivates those same rules.

The runtime database is also local: Compose starts PostgreSQL 16 on `127.0.0.1:54329` and persists
it in the `bsmart-x-postgres` Docker volume. On each `make x-local-up`, the bootstrap command copies
only the formal X ranking from `data/dev.db` into local PostgreSQL before starting the services.
Realtime posts, Calls, read models, portfolio state, and installation sessions then remain local;
the existing remote `DATABASE_URL` is not used by this stack.

Required secrets are `TWITTERAPI_IO_KEY` and a random `BSMART_X_WEBHOOK_TOKEN` of at least 24 characters. The full configuration template is `services/x_ingest/x-ingest.env.example`.

## Health and alerts

`GET /health` exposes:

- `ingestionLatencyP95Seconds`, target `<=120`;
- `readyLatencyP95Seconds`, target `<=900`;
- `queueDepth` and `oldestQueueAgeSeconds`, oldest target `<=900`;
- `processingSuccessRate24h`;
- `reconcileRecoveredPosts24h`, which makes webhook misses visible;
- `streamRecoveredPosts24h`, which separates provider catch-up payloads received after a socket opens;
- `streamConnected`, `streamConnectedAt`, `lastStreamHeartbeatAt`, and `streamLastError`;
- `latestRawPostAt`, `latestRawIngestedAt`, `latestReadyPostAt`, and `postStatusCounts24h`;
- `failedRuns24h` for historical diagnosis, `currentFailedJobs` for the current service state, active subscriptions/rules, and last successful jobs;
- `estimatedCost24hUSD`, month-to-date cost, projected `estimatedMonthCostUSD`, and the configured cost limit.

Algorithm-version reprocessing preserves each post's first successful `processed_at`, so historical maintenance does not inflate the realtime SLA. Each current Call still exposes its own `ready_at` as the Client API `processedAt` value.

The Client API returns three distinct freshness headers on Smart Account and Smart Money collections:

- `X-BSmart-Data-As-Of`: when the API checked/materialized the response;
- `X-BSmart-Latest-Content-At`: when the newest qualified source item was published or observed;
- `X-BSmart-Source-Item-Count`: how many source items back the response.

The iOS app displays checked time and latest qualified-content time separately. A recent check with an older latest-content timestamp means the pipeline is alive but no newer item passed the product policy; it must not be presented as a failed refresh.

An enabled service with an empty active author pool or no active provider rules is degraded. Cost includes matched-post provider charges and the configured per-post extraction/translation estimate; fixed worker, PostgreSQL, and logging spend remains an infrastructure budget. The worker logs ERROR when that invariant or a latency SLA is violated, WARNING for failed/partial runs, and CRITICAL when projected monthly variable cost reaches the configured limit. Connect these structured process logs to the production alerting service.

Run a billable completeness audit after the canary and periodically thereafter:

```bash
make x-ingest-audit HOURS=24 MINIMUM=0.99
```

The command re-queries active rules using bounded time windows, compares provider post IDs with PostgreSQL, prints missing IDs, and exits nonzero below 99% or when any rule cannot be audited.

## Failure behavior

- Duplicate or out-of-order webhook/reconciliation deliveries are idempotent on `post_id`.
- Provider 429 and 5xx responses retry with bounded backoff. A failed rule does not block other rules.
- Model or translation failure keeps the post in retry state; no partial view or notification is published.
- Search saturation recursively splits the time range. Exhausting the request budget fails the reconciliation run instead of claiming completeness.
- New rules are activated before old rules enter a 24-hour retiring overlap. A retiring rule that becomes desired again is reactivated without leaking a provider rule.
- Daily compliance checks remove missing/deleted source posts and their events from the next partitioned publication.
- Hyperliquid and X use producer-partitioned Read Model transactions, so either publisher can restart independently without deleting the other's documents.

## Emergency stop and rollback

Set `X_INGEST_ENABLED=false` and restart both processes. The API rejects new callbacks with 503 and every scheduled worker job skips. Existing ready documents remain available for investigation. Do not call the broad `RealtimeReadModelPublisher.clear()` during an incident because it also removes other realtime producers; removing the X overlay requires a reviewed database maintenance change.

Provider replacement must implement `pipeline.platforms.x.realtime.provider.TweetProvider`. Domain extraction, database contracts, Client API responses, and iOS models must not depend on TwitterAPI.io-specific payloads.
