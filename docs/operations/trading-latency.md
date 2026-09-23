# Trading Latency

Updated: 2026-09-23

## Read-Only Failure Recovery (2026-09-23)

The first slow info WebSocket request previously spent 4 seconds before the
bounded HTTP fallback. An order-only account observation expires after 5 seconds,
so that delay could make a valid HTTP result unusable. The socket timeout is now
1.2 seconds; only a typed socket outage or a server 5xx may use HTTP. Rate limits,
client errors and malformed socket responses still fail closed.

The order-only snapshot now cancels outstanding info reads at its 5-second
deadline. If one observation has already expired, the order store repeats that
read-only observation once. It does not retry signing, an exchange write, or an
unknown submission. The existing pre/post-sign checks and 15-second account,
5-second book and 60-second intent expiry remain in force. Two consecutive slow
reads still stop the order, and a server-side outage cannot be masked by the UI.
The selected market, order amount and leverage are not silently changed.
`TradingReadLatency` now records only an allowlisted read type, transport, coarse
outcome and elapsed time. It never logs the wallet address, coin, response body,
token, signature or order payload. A genuine 429, a transport failure and an
expired observation can therefore be distinguished in device logs.

Native regression tests exercise the one-shot order boundary, read-only fallback,
network rejection and freshness retry. Device-network p50/p95 and actual funded
order completion still require measurements; these code changes do not establish
a guaranteed 5-second execution time.

One opt-in simulator run on 2026-09-23 used a public address and an existing
`xyz:SNDK` market. All nine preflight samples were valid. HTTP's three samples
were 6.12/4.95/5.14s for the older two-round snapshot; socket-preferred with
that same snapshot was 7.66/4.71/4.50s; socket-preferred with the order-only
concurrent snapshot was 5.24/1.86/1.89s. The simulator's proxy forced HTTP
fallback during the socket-preferred run. These values include book and fee reads
but exclude wallet registration, opinion attribution, signing and exchange writes.

## Findings

The screenshot's elapsed seconds count from the slide, not from the start of
"Checking latest balance". The label identifies the current phase; it does not
prove that the whole duration was spent in that phase.

The former opening flow performed 31 Hyperliquid info reads with unchanged
leverage, or 39 with a leverage update. It built a review during the deliberate
slide, then fetched the same full review again immediately before signing. Each
snapshot itself keeps two ordered active/position observation rounds bracketed
by mode reads. Wallet registry/attribution also introduce external round trips.
These are client orchestration costs, not exchange matching time.

## Product And Infrastructure Research

- [Privy's Fomo case study](https://blog.privy.io/blog/turning-trading-into-a-social-experience-with-fomo)
  confirms embedded self-custodial wallets. It does not publish a reproducible
  Hyperliquid order latency benchmark or Fomo's full execution architecture.
- [Privy's Liquid case study](https://blog.privy.io/blog/redefining-mobile-trading-with-liquid)
  describes Hyperliquid plus Privy for a native trading app. This is the closest
  verified stack match to bSmart, not evidence that every order completes in 5s.
- [Privy's Hyperliquid quickstart](https://docs.privy.io/recipes/hyperliquid-guide)
  uses Privy, viem and `@nktkas/hyperliquid`. Its TypeScript SDK example is useful
  for server/web integration; embedding a second JavaScript signing environment
  into the native app is not required to fix redundant public reads.
- [Hyperliquid WebSocket post requests](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/post-requests)
  support the same info requests over one multiplexed connection, with unique
  request IDs and typed responses. bSmart uses Apple's URLSessionWebSocketTask
  to access that official protocol, not a custom matching service or signer.
- [Privy's latency update](https://privy.io/blog/reducing-trading-latency-on-privy)
  discusses signing infrastructure improvements and a separate fast Solana swap
  API. The Solana swap number is not a Hyperliquid perpetual order guarantee.
- [Agent wallets](https://docs.privy.io/recipes/hyperliquid/agents-and-subaccounts)
  are an established option for delegated trading, with extra consent, expiry
  and revocation requirements. They do not remove redundant balance reads.
  This change does not create agents, grant server signing authority, or modify
  custody. Revisit only if measurements identify signing as the bottleneck.

## Implemented Boundary

1. Share a single official info WebSocket across native execution readers.
   Existing entry reads warm it before the user slides. No balance response is
   cached, no timestamps are renewed, and each caller retains its own account,
   market and freshness validation. An inactive socket can reconnect.
2. Match replies by ID and expected query type. Bound concurrent requests and
   message sizes. Cancellation and late replies cannot satisfy another request.
   Connection failure/a 4s timeout falls back to bounded HTTP reads and suppresses
   reconnect attempts for 60s. Server errors and malformed replies fail closed.
3. Order-only preflight reads metadata, mode, active capacity and positions
   concurrently in one round, with a 5s network-age bound. There are still two
   independent observations around signing, comparing exact market, account
   mode, leverage and position, rejecting regressing position timestamps and
   rechecking available capacity. Repeated endpoint reads are not an atomic
   exchange snapshot; actual fill-time risk enforcement belongs to Hyperliquid.
   The original bracketed snapshot provider remains for other consumers.
4. The same slide's immediate, still-valid review is its pre-sign proof. A
   separate manual review/confirm continues to refresh. A slow attribution that
   outlives the book deadline stops without signing. Post-sign independent
   account/book/fee/authority reads still precede submission. Ordinary opening
   requires 15 info reads, or 20 after a leverage update.
5. Registry verification overlaps the initial snapshot, and pre-sign registry
   verification overlaps attribution. Local revision/lease checks remain after
   awaits; fresh registry validation also occurs after signing. Account mode
   changes between reviewed and submission snapshots now explicitly block.
6. Signing, encrypted journaling, nonce/cloid, IOC price limits, exact quantities,
   leverage confirmation, expiry and single-use submission remain unchanged.
   Writes do not move to WebSocket or acquire retry/fallback logic. Unknown
   exchange responses remain uncertain and cannot be resubmitted automatically.

## Verification And Acceptance

`HyperliquidInfoConnectionTests` exercises multiplexing, scalar payloads, malformed
replies, cancellation, timeout and cooldown. Order tests cover the reduced request
count, slow attribution, balance/mode changes after signing and one-shot writes.

Final targeted native regression: 112 tests passed, including embedded signing,
nonce ownership, codec, lifecycle, broadcast and transport failure cases. The
legacy lifecycle/signing fixtures now select fee/book responses by query type,
not concurrent arrival order. Signed generic iOS device build, `make arch-check`
and `git diff --check` passed. Apple sign-in/push remain temporarily disabled for
device testing; no production wallet or order was used for validation.

Opt-in `HyperliquidTradingLiveTests.testReadOnlySocketAndHTTPPreflightLatency`
compares native transports on a public address without signatures or writes.
It records unsuccessful samples too: a probe finishing is not proof of a fast
or valid snapshot. These samples exclude authentication, signing and exchange
submission and must not be reported as end-to-end trading latency.

### Read-only Native Measurements (2026-09-22)

iPhone 17 Pro Max simulator, iOS 26.3, same public account and `xyz:SNDK`,
three consecutive samples per mode. The current Mac HTTP/HTTPS/SOCKS proxy
remained enabled; no network settings were changed. Each sample includes one
account preflight followed by concurrent book/fee reads.

| Transport and preflight | First sample | Second | Third |
| --- | ---: | ---: | ---: |
| HTTP, original sequential rounds | 6.44s | 4.86s | 4.92s |
| WebSocket, original sequential rounds | 7.55s | 5.14s | 5.44s |
| WebSocket, concurrent order observation | 3.75s | 1.73s | 1.71s |

All nine final samples returned valid data. Earlier probes encountered stale
observations and proxy timeouts. Three samples per mode are diagnostic, not a
production percentile or reliability claim. WebSocket alone did not improve
this run: removing sequential observation rounds produced the improvement.
This measurement excludes Privy signing, wallet registry, attribution and order
submission; no funded orders or signatures were created for this benchmark.

In Xcode/device Console, filter subsystem `today.bsmart.ios` and categories
`OrderLatency` / `TradingReadLatency`. The former records per-operation start,
snapshot/registry boundaries, signing, rechecking and exchange response; the
latter identifies WebSocket or HTTP fallback and elapsed milliseconds. No
address, access token, signature, order payload or position is logged.

Acceptance target: warm, unchanged-leverage slide to exchange response within
5 seconds on a healthy supported network. Measure real user-approved trades
separately for first trade, leverage change, wallet unlock, reconnect and weak
network. Exchange response, partial fill and complete fill remain distinct.
Report p50/p95 and failure rate; do not claim a universal 5-second guarantee.
