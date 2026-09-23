# Trade Feed

September 12 integration: signed-in native clients now use the Supabase Feed
service and real pre-submission attribution. The older installation-auth API
below remains for compatibility. Deployment prerequisites and current semantics
are in `supabase_trade_feed.md`; earlier rollout status below is historical.

Updated: 2026-09-11. Native Feed replaces the AI root tab. AI opens full-screen
from the profile's lower-right circular button; only its own tab-visibility token
is released on dismissal. This is a read feature and a quick-trade UI, not a new
real-money executor.

## Content unit and fields

One item = one authenticated user's opinion-attributed exchange order with
positive, independently verified mainnet fills. Multiple partial fills of that
order aggregate into one item; multiple orders remain separate items.

```
Trade
├─ Trader: public ID / username / handle / avatar → public profile and public trades
├─ Source: opinion ID / author ID / platform / platform percentile → author
│  └─ Original opinion / publication time / ticker → existing opinion detail
├─ Execution: stable event ID / first fill time / order side / filled USD notional
└─ Instrument: ticker / market coin → ticker detail and exact-market quick trade
```

| Field | Type / source | Use | Existing / gap addressed |
|---|---|---|---|
| id | UUID derived from verified account/venue/order key | identity/dedup | new public event identity |
| trader.id/nickname/handle/avatarURL | canonical Supabase account profile (nickname is wire-compatible username) | display/navigation | existing public profile |
| opinion | existing SmartAccountUpdate from server-owned catalog | evidence/navigation | reused, no client-generated opinion |
| opinion.platformPercentile | existing server ranking, 0…0.25 | eligibility/badge | reused; not recomputed on device |
| executedAt | earliest exchange fill UTC timestamp | descending sort/display | existing fill timestamp |
| side | long/short, submitted order side | color/display/quick action | existing verified order direction |
| notionalUSD | positive decimal string, sum of filled USD values | amount display | new optional fill value; never margin or P&L |
| marketCoin | exact verified Hyperliquid market identifier | quick execution | new optional fill identity |
| feedVisible | separate explicit consent including amount disclosure | eligibility | new; old trader-list consent does not enable Feed |

The opinion is evidence; a trade through it does not prove psychological causation
or endorsement. No synthetic investment conclusion or inferred user identity.
Only an original text/evidence excerpt is quoted; AI thesis fallback is separately
labelled as a summary. Different market venues must not silently substitute.

## API and source boundary

`GET /v1/trade-feed?offset=0&limit=30[&profileId=UUID]` returns
`{items: TradeFeedItem[], nextOffset: Int?}`. Existing `/v1/feed` remains portfolio
signals. `GET /v1/public-traders/{profileId}` returns the current consented public
profile, or 404 after withdrawal/deletion. Both require installation bearer and
are no-store; unavailable source is 503, not an empty success.

`TradeFeedRepository.register_opinion` accepts an opinion ID and reads its author
and evidence from the server-owned read model; it does not accept arbitrary
client-provided text/rank. Eligibility is explicit platform Top 25%. The context
must be registered before an order can appear; absent/withdrawn context excludes
the order. The real reconciler supplies filled USD notional and exact market coin
to `ConfirmedOpinionFill`; no public POST creates fills or Feed items. No historical
trade gets opinion attribution retroactively.

Pagination is live. Order by first fill descending then stable order keys; an
updated partial fill changes amount, not event ID/time. Clients replace duplicate
IDs and refresh on return/foreground. Failed pagination keeps existing items;
failed refresh clears stale public identities. Leaving Feed clears public records
from its view store. Public profile reads recheck current consent. Account deletion
uses the existing transactional removal of fills and profiles.

## Quick trade and rollout

The footer contains the asset logo/ticker followed by equal-sized Long and Short
buttons. The four fixed $100/$500 blocks are removed. `FeedQuickTradeBar` opens
the shared `BSmartTradeSheet` with the exact coin, direction and original opinion
source, but no preset amount. Users enter their own amount in the existing trade
composer. Opening a sheet never executes an order. Explicit confirmation uses
the device-signed, durable IOC lifecycle defined by `hyperliquid_execution.md`;
no fallback to paper fills or a second automatic order on repeated taps exists.
Existing positions can be reduced or reversed by a non-reduce-only order and
the user's current venue leverage is shown instead of silently changed.

Production execution remains closed pending funded acceptance. Local execution
receipts never publish themselves to the real Feed. Server-side reconciliation
and authenticated public-profile/amount-sharing consent services remain prerequisites.
The migration script is prepared for operator review and is not run by this task.
The production Feed no longer exposes a Demo toolbar entry. Debug layout tests
explicitly launch `--ui-feed-layout-preview`, which loads six fictional trades
from `trade-feed-demo.json` on an isolated `FeedLayoutPreview` surface. Release
builds exclude this surface. It never replaces a failed live request. Test examples
are labelled on the navigation title, every row and local profiles. Source opinions are
existing catalog records; trader identities, amounts and relative execution times
are examples. `TradeFeedDemoData` freezes the preview timeline when entering,
filters local profile pages and preserves pagination. `FeedDemoTradePreview`
shows the chosen side and ticker only, with no preset notional, order executor, signer,
balance writes or live Feed publication.

## Local verification — 2026-09-11

Debug iOS build passed. Eight Feed unit tests passed, including existing 5x
leverage with $100 requested notional, duplicate execution prevention, cancellation,
pagination and visibility-token ownership. Eight relevant native UI cases passed
across the initial run and final retest: four Feed cases, two profile regressions,
typed AI conversation, and AI → evidence → AI → profile navigation. The final five
Feed/navigation cases passed together on iPhone 16 / iOS 18.5. Header gesture
grouping and the execution row's accessibility container were corrected during QA.

Twenty ledger/Feed Python tests, OpenAPI schema and Feed fixture validation,
architecture, terminology and diff whitespace checks passed. The complete native
unit run executed 618 tests with three skips and 20 failures in existing Keychain
storage checks (including missing entitlement error -34018). The general fixture
contract check stops at Smart Money evidence `cab821de-fb9b-560e-9a72-09ea258f3a07`
with missing market candles; that unrelated data was not modified for this feature.
These results do not establish production Feed availability or real execution.
