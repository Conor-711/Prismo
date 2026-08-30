# Hyperliquid Platform Adapter

Read-only adapter for Hyperliquid HIP-3 TradFi perpetual markets.

## Responsibilities

- discover every TradFi instrument declared by `perpCategories` and refresh the
  active directory while the live worker is running;
- subscribe to every active instrument's public `trades` WebSocket feed;
- persist an idempotent public trade tape containing both buyer and seller;
- discover candidate addresses from that tape and maintain per-wallet fill
  cursors;
- page `userFillsByTime` for exact position transitions;
- fetch all-DEX account state in batches through the public
  `allDexsClearinghouseState` WebSocket snapshot;
- fetch lower-frequency portfolio history and non-funding ledger events;
- persist normalized instruments, wallets, fills, immutable account/position
  snapshots, current positions, performance history and capital activity.

The adapter does not decide whether a wallet is Smart Money. Qualification,
Onchain Score, cohort assignment and asset signals live in
`pipeline/domain/smart_voice/hyperliquid.py`.

## Realtime model

The public trade tape is the loss-minimizing discovery layer. Fill and profile
enrichment run in background workers so a slow 10,000-fill history request
cannot stop the trade stream or minute-level Read Model publishing. Activity
from already-qualified wallets is refreshed before unqualified discovery work.
Low-latency active enrichment and historical catch-up use independent bounded
batches, so neither lane can starve the other.

The historical candidate cohort is capped at the 500 highest observed-notional
wallets active in the last 30 days that have crossed either 5 observed trades
or USD 10,000 observed notional. This controls an otherwise unbounded counterparty universe while
retaining the overwhelming majority of observed TradFi flow. Candidate
selection is not qualification: only complete fill history can enter formal
directional scoring.

`HyperliquidInfoClient` serializes and paces REST requests below the documented
IP budget, retries `429` responses, and accounts for response-size weight. The
trade WebSocket reconnects with backoff and supports runtime subscription
changes when instruments appear or disappear. `HYPERLIQUID_WS_PROXY` can
override system proxy discovery.

## Coverage semantics

`userFillsByTime` returns at most 2,000 rows per response and exposes only the
latest 10,000 fills. Formal scoring already excludes accounts with 2,000 fills
inside the score window, so first-pass enrichment stops at that policy ceiling
instead of downloading up to 10,000 unusable rows. A successful pass sets
`fills_backfill_complete=1`; `fills_limit_reason` distinguishes
`policy_algorithmic_2000` from the legacy/source `source_10000` ceiling.
Limited/high-frequency accounts remain auditable but are excluded from
directional scoring, and future refreshes continue from the stored cursor.

Health therefore reports both:

- `fillBackfillCoverage`: current top-500 candidate wallets whose
  available-source catch-up pass finished;
- `fullHistoryCoverage`: wallets whose pass finished without the 10,000-fill
  source ceiling;
- `historyLimitedWallets`: explicit source-limited accounts.
- `policyLimitedWallets` / `sourceLimitedWallets`: the auditable reason split.

The candidate pool is ranked from activity observed after the continuous public
trade tape starts; it is not a complete list of accounts active before that
checkpoint. This limitation must remain visible in product methodology.

Only categories declared by Hyperliquid as stocks, indices, commodities, FX or
pre-IPO are included. Crypto markets are excluded.

## Commands

One-shot recovery or research run:

```bash
pipeline/.venv/bin/python -m pipeline.manage hyperliquid-smart-money \
  --stage all --lookback-days 30 --max-wallets 64 \
  --db data/dev.db \
  --output web/lib/data/hyperliquidSmartMoney.json
```

Continuous worker:

```bash
make hyperliquid-smart-money-live
```

Production startup, health fields, publisher ordering and restart behavior are
defined in `docs/operations/hyperliquid-smart-money-live.md`.
