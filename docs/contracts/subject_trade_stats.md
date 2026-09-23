# Subject-attributed trades

2026-09-13. Extends the Supabase verified Feed ledger, not the execution engine.

- `GET /bsmart-feed/subject-stats?kind=account|money&id=...&platform=...`
  requires the existing native Supabase user session. Platform is mandatory for
  account subjects and is `hyperliquid` for money subjects.
- Count distinct `(account_id, opinion_id)` pairs across a subject's verified
  sources, all-time. One user trading ten opinions contributes ten; repeat fills
  of one opinion contribute one. This is **Trades inspired**, not unique people,
  raw orders, exchange volume or proof of causation. Latest verified opening fill
  per pair determines long/short. No Top-25% restriction on the subject total.
- Group by server catalog `authorId`, `platform` and `sourceKind` (legacy absent
  kind means `account`). Never infer attribution from ticker or client claims.
- Money sources are reviewed public movement snapshots in the same private
  catalog, with `sourceKind=money`, canonical `authorId`, `platform=hyperliquid`,
  movement UUID as `id`, `marketCoin` and observed time as `publishedAt`.
  They have no social percentile, so existing social Feed/popular projections do
  not mislabel them as investment bloggers. The money owner's trades themselves
  never count: only users' independently verified, pre-linked executions do.
- Money detail links to movement detail, whose trade dock carries that movement
  source. Ordinary trades, including ticker navigation, are not attributed.
- Response: `kind`, `subjectId`, `platform`, `totalTrades`, `longTrades`,
  `shortTrades`, `sourceCount`. The direction sum equals total; sourceCount counts
  sources with at least one pair. No wallet, user ID, amounts or identity exposed.
- Empty verified result is zero; missing migration/service is 503, not zero.
  Account changes, logout/background and profile revisions invalidate the native
  state. Account deletion cascades existing ledger contributions as before.
- Migration `202609130001_subject_trade_stats.sql` is operator-applied only.
  Deploy Edge Function and publish reviewed money catalog before using its dock.
  No retrospective synthetic attributions or actual order submissions in tests.

Author detail keeps core labels, values, chart controls and source links. Repeated
reference-price/OHLC/disclaimer helper lines are removed. Price change remains
explicitly labeled; full data methodology and limitations are available inside
the existing collapsed calculation disclosure, not repeated across sections.

## Rollout verification

2026-09-13: read-only production probes confirmed the new RPC is available.
`bsmart-feed` is deployed. The private active catalog contains 1,686 sources:
1,466 existing social opinions and 220 reviewed money movements. All immutable
objects uploaded before activation; transient object uploads retry identical
bytes up to three times, without activating a partial catalog.

The existing three verified executions aggregate into two X subjects with totals
of one (short) and two (one long/one short), confirming real data is being used.
Scheduler health remains ready. No real order, signature, user/profile or fill
was created by this task, and no production DDL was executed by the assistant.
Money-source user execution still requires the user's real interaction; the
catalog and native source binding are not proof that anyone has followed it yet.

Verification: 44 Deno tests, 14 Python catalog/context tests, 47 selected native
unit tests and two chart/profile UI workflows passed. The final shortened-profile
UI run also passed after updating test scrolling to avoid the interactive plot.
