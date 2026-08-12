# Vultr production deployment

This stack runs the iOS Client API and the X Smart Account realtime pipeline on one small Vultr
instance. PostgreSQL is reachable only from localhost, while Caddy is the only public service.

## Services

- `postgres`: runtime state and read models.
- `postgres-backup`: daily custom-format database dump with seven-day retention.
- `client-api`: authenticated iOS data API.
- `x-ingest-api`: TwitterAPI.io webhook receiver and ingestion health.
- `x-worker`: top-quartile rule sync, reconciliation, processing and publication.
- `caddy`: HTTPS termination and routing.

## Deployment order

1. Create `.env.production` from the example with mode `0600` and keep
   `X_INGEST_ENABLED=false`.
2. Start PostgreSQL, Client API, X API and Caddy.
3. Run `scripts/bootstrap_x_realtime.py` against PostgreSQL and publish the current Client API read
   models.
4. Verify `/health`, authenticated Client API reads and `/x-health`.
5. Set `X_INGEST_ENABLED=true`, start `x-worker`, then verify provider rules and freshness.

Use `BSMART_X_POOL_LIMIT=0` for the complete formal top quartile. It does not select the complete X
ranking. The first production rollout may temporarily use a positive canary limit.

The temporary `sslip.io` hostname is suitable for development and internal testing. Before a
TestFlight release, point `api.bsmart.today` at the server, change `PUBLIC_HOST`, and let Caddy obtain
the production certificate.
