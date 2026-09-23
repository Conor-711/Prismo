# Trade thesis — 2026-09-22

A user-authored explanation attached to one independently verified opinion-linked
opening order. One immutable thesis per trade, quoting the server-registered
opinion snapshot. Publishing never signs, executes or modifies an order.

## Content decomposition

```text
Trade + thesis
├─ Trader: public profile ID, username, handle, avatar
├─ Execution: event ID, instrument, side, notional, execution time
├─ Theory: original user text, publication time
├─ Quote: registered opinion ID, author, original text/summary
└─ Interaction: likes, viewer liked state, owner publishing eligibility
```

| Field | Type/source | Use | Existing/gap |
| --- | --- | --- | --- |
| trader | Public profile, server | Identity/navigation | Existing |
| id / side / notionalUSD / executedAt | Verified exchange aggregate | Execution evidence/order | Existing |
| opinion | Immutable registered snapshot | Quote/detail navigation | Existing |
| thesis.body | 1–1000 Unicode scalars, user original | Main text | New |
| thesis.publishedAt | Server timestamp | Publication history | New |
| thesis.likeCount | Unique authenticated accounts, computed | Interaction count | New |
| thesis.likedByMe | Server viewer projection | Like/unlike | New |
| canLikeThesis | Server viewer is not author | Like/unlike eligibility | New |
| canPublishThesis | Verified owner and absent thesis | Composer action | New |

No AI rewrite, sentiment inference, performance inference or popularity percentile
is needed for this chronological feed. Text precedes the existing opinion quote;
execution facts retain their existing layout. Publication time is separate from
execution time; publishing and liking never bump trade chronology.

## Persistence and APIs

Migration `202609220004_trade_theses.sql` adds isolated thesis and like tables with
RLS and no anon/authenticated table/RPC grants. Edge authenticates the native
Supabase user and passes that identity to service-role RPCs. Account IDs/wallets
never appear in public responses. Account/order deletion cascades to theses/likes.

- GET Feed with `includeTheses=true` enables the new projection; omitted/false
  keeps the legacy Top-25% response so older clients do not reject lower-ranked
  quoted authors.
- GET Feed with `includeTheses=true&mine=true`: all my verified social opinion trades, allowing later
  publication after dismissing the fill screen or restarting. Cannot combine with profileId.
- GET `/orders/{cloid}/activity`: my verified trade; 409 while verification is pending.
  Missing thesis RPCs return 503 `thesis_not_ready` for activity/publication/likes; other service failures remain `feed_unavailable`.
  The fill screen reads activity first and requests exchange reconciliation only when pending.
  Its write action is a full-width 52pt button above Done.
- PUT `/trades/{id}/thesis` with `{body}`: create once; same text retry returns the
  existing object, changed text is 409. Ownership, source and execution checked in SQL.
- PUT `/theses/{id}/like` with `{liked}`: explicit desired state, idempotent per user.
- Feed returns optional thesis and canPublishThesis. Existing legacy responses remain decodable.

Plain trades keep the Top-25% source rule. A published user thesis appears regardless
of quoted social author's percentile (0–1); Smart Money source snapshots remain
outside this feed. Own history includes all social sources for later writing.
Recent feed/profile lists remain ordered by executedAt desc, event ID tie-breaker.

Drafts remain in the composer on request failure; retry cannot duplicate a thesis.
Account switching clears the composer. Published theories cannot be edited in v1.
Other users can like/unlike; authors cannot like their own thesis.

## Reference and rollout

Fomo documents attaching reasoning to trades in January, then global feed display
and likes in February. bSmart additionally quotes the original Smart Account opinion.
https://fomo.family/blog/january-2026-recap
https://fomo.family/blog/february-2026-recap

Operator must apply migration before deploying bsmart-feed and releasing the app.
The assistant prepares SQL and verifies it in an ephemeral test database only;
production DDL is not executed. No production deployment or real trades are implied.

## Local validation — 2026-09-22

- 19 Deno tests pass across the thesis, existing Feed and real PGlite schema suites;
  final thesis-only rerun also passes after adding owner lookup isolation and the
  owner-history index. Covers ownership, pending verification, source eligibility,
  immutable/idempotent publication, like/unlike deduplication, profile/feed parity,
  legacy response compatibility, RLS and account deletion cascades.
- iOS simulator build and 21 selected native tests pass on iPhone 16 / iOS 18.5:
  `TradeThesisTests`, `TradeFeedTests`, `NativeFeedSessionTests`.
  Default build first hit a shared build-db lock; a generic simulator build then
  hit AssetCatalogSimulatorAgent failure during concurrent resource changes.
  Final verification used isolated `/tmp/bsmart-thesis-derived` and two build jobs.
- Edge type checks, OpenAPI YAML + new fixture schema validation, architecture,
  terminology and whitespace checks pass. No screenshot-based acceptance,
  production database migration, service deployment or real trading was performed.

## Rollout repair — 2026-09-22

The live activity RPC initially returned PGRST202 (missing function). The operator
then confirmed manual migration success; a service-role read of the owner-scoped
projection using a nonexistent actor returned 200 and an empty list. bsmart-feed
was deployed after this check. No production thesis, like or order was created.
The full-width button and read-before-sync behavior require a new app build.
20 Edge regressions and 11 native tests passed; iOS build, Edge type checking,
architecture, terminology and whitespace checks passed.
