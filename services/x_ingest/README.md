# X Smart Account realtime service

This service monitors the formal X Smart Account top quartile. The webhook API only normalizes and stores provider deliveries; the worker owns pool/rule synchronization, 15-minute reconciliation, complete Call processing, read-model publication, and deletion checks.

Production requires PostgreSQL for both `BSMART_X_DATABASE_URL` and `BSMART_READ_MODEL_DATABASE_URL`. Configure the TwitterAPI.io callback URL as:

`https://<ingest-host>/webhooks/twitterapi-io/<BSMART_X_WEBHOOK_TOKEN>`

When ingestion, Client API state, and read models share one PostgreSQL database, setting only
`DATABASE_URL` is sufficient. Explicit `BSMART_*_DATABASE_URL` values remain available for a
split-database deployment.

Run locally:

```bash
make x-ingest-install
make x-ingest-bootstrap POOL_LIMIT=10
X_INGEST_ENABLED=true make x-ingest-api
X_INGEST_ENABLED=true make x-ingest-worker
```

For a persistent, fully local stack, use the provider's outbound WebSocket transport. This avoids
a public callback or tunnel while retaining the same filter rules and 15-minute REST reconciliation:

```bash
# Copy the TwitterAPI.io API key in the provider dashboard first.
make x-local-config
make x-local-up
make x-local-status
```

The ignored `.env.x-realtime.local` stores the provider key and generated webhook token with mode
`0600`. Docker Compose keeps local PostgreSQL, the X API, X worker, and Client API alive with
`restart: unless-stopped`. PostgreSQL is bound to `127.0.0.1:54329`; its Docker volume survives
`make x-local-down`. The local bootstrap imports the formal ranking from `data/dev.db`, while all
new runtime data stays in PostgreSQL rather than the configured remote database.
Use `make x-local-down` rather than raw `docker compose down`; the Make target pauses the mapped
provider rules before stopping containers and `x-local-up` reactivates them.

`X_INGEST_ENABLED=false` is the emergency stop. It rejects callbacks and causes scheduled jobs to skip work. Existing ready documents remain readable.

The default runtime uses a fixed author pool (`BSMART_X_FREEZE_AUTHOR_POOL=true`). Bootstrap once with `POOL_LIMIT=0` to snapshot the complete formal top quartile; subsequent worker restarts synchronize TwitterAPI.io rules from that stored subscription pool without recalculating Smart Account scores or replacing its members. Set `BSMART_X_FREEZE_AUTHOR_POOL=false` only when a reviewed ranking refresh should change the monitored authors. `BSMART_X_PROCESS_WORKERS` controls parallel Call extraction and complete translation; the default is four.

The worker publishes two producer-partitioned collections: `smart-account-updates` and the corresponding `account_leads` entries in `portfolio-signals`. Partitioned publication retains non-X Smart Account documents and Hyperliquid signals. Run the SQL migrations before starting either process.

Operational setup, health thresholds, completeness audit, rollback, and deployment order are documented in `docs/operations/x-smart-account-realtime.md`.
