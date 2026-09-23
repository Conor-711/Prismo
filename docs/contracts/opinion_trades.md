# Opinion-attributed real trades

September 12: native live orders now carry source/author identity into a server
registration before signing; signed-in count/list reads use the Supabase Feed
service. See `supabase_trade_feed.md`. The following source-off/legacy deployment
descriptions are historical; new SQL and Edge deployment are still required.

## App preview (2026-09-11)

At the user's request, an explicit local demo is visible when there is no
verified response (including loading/unavailable). `OpinionTraderDemoData` is
not `OpinionTradersPage` and is never submitted to the ledger. Six fictional
first names use distinct bundled illustration avatars; two private sample users
bring the sample count to eight. Entry price, notional, leverage and opening
time are illustrative only, including when a historical reference price is used.
The header and footer label this demo. Verified responses, including zero,
replace it entirely; a later failed refresh never mixes examples into live rows.
This does not change the real API's privacy policy or expose position sizes.

Status: implemented read UI and verified-ledger boundary; real execution is not
enabled. PaperTradingEngine must never publish to this ledger. No migration is
applied automatically. Deploying UI alone cannot produce real trader counts.

## Counting and attribution

- Key: stable opinion/call UUID. Count distinct authenticated account IDs, not
  clicks, orders, installations, fills or wallets. Multiple orders from one user
  under one opinion count once, across long and short directions.
- Carry `OpinionTradeSource(opinionId, ticker, feedEventId?)` only from the opinion
  detail’s own trade dock or an explicit Feed quick action. Feed retains its event
  ID as context, but the server must independently bind the source. Do not
  propagate it through ticker navigation or other docks.
- The future real executor must bind that source to its authenticated order
  record BEFORE submission, validate the opinion/ticker against the server
  catalog, and use a unique exchange client order ID. A browser/client claiming
  a completed trade is never sufficient evidence.
- The reconciliation adapter independently verifies mainnet fill ID, wallet
  ownership, market, order/client-order ID, positive fill quantity, finality and
  exchange timestamp. Only then may it write `ConfirmedOpinionFill`. Partial
  positive fills count; resting, rejected, simulated, testnet and deposit events
  do not. Duplicate venue/fill IDs are idempotent; changed duplicates are errors.
- Imported historical wallet trades cannot retroactively acquire a source.
  This measures trades through the page, not proof the opinion caused a decision.

## Privacy

Total includes everyone. The expandable list includes only accounts with
explicit public-list consent, latest canonical avatar/username/handle, latest execution direction
and timestamp. Sort newest verified fill first, then stable public profile ID.
This people list does not expose wallet addresses, account IDs, quantities, sizes
or P&L. The separate Trade Feed may expose filled USD notional only after explicit
amount-sharing consent (`feedVisible`); see `trade_feed.md`. Default is
private. Consent/profile updates originate in authenticated account services, not
read requests or fill claims. Revocation immediately removes identity from lists
without reducing the distinct trader count. Local profile files are NOT public
server profiles and must not be uploaded implicitly.

Account deletion is different from withdrawing public-list consent. The account
deletion transaction removes that account's public profile and attributed fills,
so its contribution disappears from both the list and distinct count. All profile
and confirmed-fill writers require a registered account in the same state database
and serialize against pending/deleted state. A delayed reconciliation or profile
request cannot recreate erased associations. Unknown/deleted accounts fail closed;
read-model fixtures do not bypass this authenticated write boundary. See
`account_deletion.md`; financial/legal retention review is still a production gate.

## Read API

`GET /v1/opinions/{opinionId}/traders?offset=0&limit=30` requires the installation
bearer, is no-store, and returns `totalTraders`, `publicTraders`, `traders`, and
`nextOffset`. Rows contain `id` (public pseudonymous UUID), `nickname`, nullable
`avatarURL`, `handle`, `side` (`long`/`short`), and `tradedAt` (UTC ISO timestamp).
The historical `nickname` wire key means the account's username. `handle` is
unique; bio is not projected into these lists. See `account_profiles.md`.
Offset pages are live, not a frozen snapshot; clients de-duplicate by public ID
and reset pagination on refresh. 503 means unavailable, never zero; failed pages
must retain prior rows. Empty verified ledger means zero only once the live
reconciliation source is operational. Source-off defaults to 503.

## Release gates

Operator review/application of `services/client_api/opinion_trades/migration.sql`,
real order submission and independent mainnet reconciliation, authenticated
public-profile/consent endpoints and order confirmation consent UX, deletion and
revocation flows, production pagination/load tests, and device end-to-end tests
are required before enabling the repository in `create_app`. This change does
not enable real trading, send orders, apply DDL or publish any personal data.
