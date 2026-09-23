# Hyperliquid Execution

Status: internal mainnet acceptance (2026-09-12), not public-release approval.
Google login is user-verified, the wallet registry is deployed, and separate
deposit/trading/withdrawal capability switches are enabled for the internal app.
The native order route supports explicit review, device signing and durable
one-shot submission. No funded transaction has been performed by the assistant.
User-confirmed funded acceptance, complete fee/reconciliation UX and independent
review remain release requirements. PaperTradingEngine stays isolated and is
not the production market-order or Feed shortcut destination.
See `native_perpetual_mvp.md` for the current wallet-to-close-to-withdraw route.

## Basic execution priority (2026-09-11)

The immediate scope is Arbitrum native USDC deposits, withdrawals and real market
orders. bSmart is a Hyperliquid frontend, not an exchange or HIP-3 deployer.
Trading is perpetual-only: no spot, options, delivery futures or outcome orders.
Funding may read shared/spot USDC or observe a fallback, but that is not a spot
trading feature and cannot be presented as verified perpetual collateral.
Builder recipient and fee are undecided: initial orders omit builder entirely;
no invented recipient, fee or implicit approval may be used.

### Native composer (2026-09-12)

The original amount, leverage ruler, keypad/chart toggle, presets, balance/MAX
and slide-to-confirm layout is restored. Input means margin; Feed notional is
converted once on entry. One slide explicitly authorizes the selected leverage
and order, with no intervening review form. Balance and fees come from the
execution reader; unavailable liquidation estimates remain blank, never simulated.

With no existing position, a changed leverage uses the fixed `updateLeverage`
action before the order. Its ordered MessagePack fields are type, asset, isCross,
leverage; signing uses the official L1 Agent hash and a 60-second expiresAfter.
The journal reserves its nonce in the shared owner sequence before signing;
one-use permits prevent duplicate signing/submission. A fresh exchange snapshot
must confirm the leverage before constructing the order. Existing positions lock
the ruler to their actual leverage. No builder approval or arbitrary action is added.

Deposit UI is amount -> Continue -> Confirm transfer. A saved, unexpired USDC
authorization can resume under its original amount, fee ceiling and deadline,
using a fresh source simulation. Chain-confirmed expired orphan authorizations
retain their evidence but stop reserving the wallet. Abandoned unsigned source
previews are cancelled in the journal; signed or sent transactions are never
cleared or resent. Authorization, submission and credited balance remain distinct.

If simulation fails before any source transaction exists, the fixed self-submitted
extension authorization is retained as `notSubmitted` and cannot be revived into
a source permit. A new explicitly requested deposit gets a new authorization
nonce. The journal checks absence of a source record atomically; an in-flight
authorization signer remains reserved. This is not
an onchain authorization revocation and does not delete signatures or history.
Arbitrum preflight obtains the gas estimate before its bounded fee-bearing call,
avoiding the node's default ~50-million-gas affordability check.

Submission rechecks use raw estimated gas <= the originally signed gas limit.
The original limit already contains 20% headroom; reapplying that multiplier at
submission incorrectly rejects even a one-unit increase. Both fresh and final
bounded estimates must fit, with no increase to the signed gas or fee-per-gas caps.
A genuine quote overrun is distinct from the fixed absolute safety limit.

For source records, only `signed -> notSubmitted` may release an abandoned
pre-submission attempt, with all signed evidence retained. `beginSubmission`
commits `submitting` before returning the only broadcast permit; the new terminal
transition and permit issuance are mutually exclusive under the journal lock.
It cannot release signing in progress, submitting, submitted or uncertain states,
or records with observed transaction/receipt/nonce/authorization conflicts.
A not-found observation alone does not block this transition. New attempts use
fresh authorization nonces and explicit confirmation; old signed bytes cannot
obtain another permit. UI restoration also handles legacy never-submitted records.

## Withdrawal boundary

### Native MVP flow (2026-09-12)

The native withdrawal destination now provides recipient/amount review and one
explicit protected confirmation. `HyperliquidWithdrawalStore` reads the default
perpetual account's `withdrawable` field and current CCTP cap, checks them again
before and after signing, and uses journal-issued one-use permits with the existing
exchange transport. Confirmation allocates a fresh shared owner nonce without
changing the reviewed recipient/amount. It never retries an ambiguous submission.
Unified USDC uses `sourceDex=spot` only after fresh all-DEX checks prove zero
positions and orders and the balance reports zero hold. No shared-margin
withdrawal capacity is inferred with active exposure. Portfolio margin remains unsupported.

This implementation uses an independent withdrawal capability gate. The CCTP
cap is labelled separately from additional HyperCore fees, with no promised net
amount. Accepted requests are shown as processing, not arrived; they cannot be
resubmitted. New explicit withdrawals require fresh balances and new nonces.
Unknown requests remain blocked. Full protocol fee checks and funded end-to-end
acceptance remain public-release requirements.
Withdrawal history now restores local encrypted journal records in the native
withdrawal screen, including accepted, rejected and ambiguous requests. A disabled
withdrawal gate still permits authenticated history reads, never signing.
The portfolio entry is next to Deposit; verified wallets use the existing hybrid
device/embedded signer. Pre-input availability uses the same mode/flat-account
validation as the signed preview, rounded down from eight to six decimals for Max.
Fresh confirmation still revalidates the full amount; displayed availability is
not signing authority. Accepted/rejected requests can begin a new explicit review;
unknown requests cannot be cleared by the UI or automatically resent.
Itemized fills and destination reconciliation screens are deferred; market-order
confirmation now returns the exchange acknowledgement without an extra fills read.

### Protocol and persistence

The outbound route is HyperCore USDC -> HyperEVM CCTP -> Arbitrum native USDC,
using `sendToEvmWithData`. Do not revive deprecated Bridge2/withdraw3. The typed
action fixes Mainnet, signature chain 42161, destination CCTP domain 3, hex
recipient, automatic forwarding and a bounded gas limit. This is the separate
HyperliquidSignTransaction user-signed scheme, not L1 Agent hashing. This action
does not support expiresAfter; a local confirmation deadline is not an onchain
revocation. A signed/unknown request must never be silently retried or expired.
Its nonce allocation must share the owner journal with orders before enabling
device signing. A codec or quote is not a signing capability.

Withdrawal records use the existing encrypted, Keychain-anchored event journal.
The owner nonce high-water mark spans orders, withdrawals and fixed unified-account setup, even across app
account IDs and cancelled reviews. A returned next nonce is only a hint; reserve
checks and persists uniqueness under the same file lock. Old order/source-only
journals replay unchanged. Arbitrum transaction nonces remain a separate domain.

Only an unsigned review may be cancelled or locally expire. Once signing has
started, elapsed time, task cancellation, sign-out and process restart cannot
release the reservation. A single validated exchange rejection is distinct from
an uncertain reply; `ok/default` means accepted, not destination arrival. Uncertain
withdrawals remain reserved pending source/destination reconciliation. Accepted
records permit new explicit actions, but never issue another submission permit.
The record-only API issues no capability; the native flow uses separate
`HyperliquidWithdrawalPermits` after validating a fresh preview. Complete protocol
fees and transfer confirmation remain release requirements.
Returned signatures and responses are evidence writes: task cancellation does not
discard them. If wall time moves backwards, their local `updatedAt` is clamped to
the previous journal timestamp; event sequence, not this display timestamp, orders
the evidence. This does not extend a review deadline or establish an onchain time.
Future signing must use a fresh dual-clock preflight and revocable lease; the
persisted review deadline alone is not authorization.

Read current CoreDepositWallet `calculateCrossChainWithdrawalFee(true, 3)` and
route configuration. This CCTP cap is not proof of the total HyperCore debit, nor
a contractual cap embedded in this action. Check total protocol fees, true
withdrawable balance and mode separately. Never use unified-account spot total
as withdrawable collateral. HTTP success means initiated only; source withdrawal,
CCTP attestation and destination mint/recipient transfer must be reconciled before
displaying arrived. Until these checks are integrated, preparation remains
read-only and the production withdrawal/signing entry remains closed.

Sources: [Circle withdrawal guide](https://developers.circle.com/cctp/howtos/withdraw-usdc-from-hypercore-to-evm),
[CoreDepositWallet source](https://github.com/circlefin/hyperevm-circle-contracts/blob/master/src/CoreDepositWallet.sol),
[Hyperliquid exchange endpoint](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint).

## Market identity

Resolve the exact exchange coin, not its display ticker. Native perps use the raw
`meta.universe` index. Builder perps use `100000 + 10000 * rawDexIndex + rawAssetIndex`.
Keep null/delisted entries in their original slots. Never infer IDs from the
filtered UI market list. Reject duplicate names, unknown DEX/coin, delisted assets,
malformed metadata and missing collateral. Preserve collateral token, size
precision, maximum leverage and isolated-only status for subsequent preflight.
Preserve the newer `marginMode` (`normal` / `noCross` / `strictIsolated`) as well as the
deprecated `onlyIsolated`; do not treat a new or contradictory mode as cross.
USDC funding does not establish trading capacity for another collateral or DEX.

## Immutable order

Execution validates the perpetual namespace even when a market was decoded from
stored data: native asset IDs remain below 10000, builder IDs retain their
documented offset; spot IDs, spot pair symbols and the reserved spot DEX cannot
produce an order. Fresh metadata resolution is still required before signing.

The native composer has Open/Add and Reduce/Close modes. Reduction percentages
are applied to an authoritative position quantity, with direction derived from
its sign. Partial size rounds down to szDecimals; a full close keeps exact size.
Every reduction is signed with reduceOnly=true, never automatically flipped to
an opening order. A quantity rounded to zero or no position returns an error.
No opening $10 minimum is used to enlarge a small residual position. Actual
exchange acceptance/fill remains authoritative; a preview is not a promise.
Confirm-time and post-signing refresh must retain the reviewed position exactly,
including its direction/size/leverage. Changed position requires a new review,
not silently resized submission. Partial IOC fills leave the remainder open.
Opening collateral checks do not block risk-reducing orders solely because no
new-position margin is available; quote/fees, position bounds, fresh checks,
authenticated signing and one-shot journal submission still apply.

Reference implementation: official Python SDK
[market_close](https://github.com/hyperliquid-dex/hyperliquid-python-sdk/blob/master/hyperliquid/exchange.py)
derives direction/size from the perp position and submits a reduce-only IOC.

The first execution action is one owner-wallet IOC limit order, grouping `na`.
It contains the exact market, buy/sell side, positive size, limit price,
reduce-only flag, a nonzero 128-bit lowercase cloid, nonce and expiresAfter.
No vault, subaccount, agent approval, leverage change, trigger or builder fee is
implicit. The price limit bounds execution; it does not promise a fill.

Prices/sizes use exact decimal strings and BigInt, never Double or formatter
output. Remove trailing fractional zeros before signing. Perp prices permit five
significant digits, at most `6 - szDecimals` fractional places; integers are exempt
from the significant-digit limit. Size must fit szDecimals. No silent rounding.
All timestamps fit JSON-safe integers. Expiry must follow nonce by at most 60s.
Intent creation validates structure, not balance, consent, session or freshness.
Only an authenticated, fresh preflight and durable intent journal may permit
device signing/submission. Cloid uniqueness and monotonic nonces need that journal;
random generation alone is not an idempotency mechanism.

## Encoding and signatures

Use BatchLabs MessagePack-Swift pinned to revision
`c6fabe5afe1261f927a448187b20e84b9af34720` (MIT, no dependencies), vendored unmodified
under `ios/Packages/MessagePack` with provenance/checksum and its upstream tests.
The app bundles its license. Use its primitive
writer with explicit map field sequence, not unordered Swift dictionaries:
action `type, orders, grouping`; order `a, b, p, s, r, t, c`.
The single limit type is `{limit:{tif:Ioc}}`. Production uses only the writer;
no untrusted MessagePack is decoded. This small older dependency is pinned and
reviewed for this encoding path, not claimed to be security-audited.

Hash MessagePack + big-endian uint64 nonce + no-vault byte 0 + expiry marker 0
+ big-endian uint64 expiresAfter using existing Wallet Core Keccak-256. Construct
the fixed EIP-712 Exchange domain (version 1, chain 1337, zero verifying contract)
and Agent(source `a`, connectionId action hash). This is the mainnet L1 scheme,
not CCTP EIP-3009 or a Hyperliquid user-signed transfer. Wallet Core computes the
typed digest; supplied signatures must be low-s v=27/28 and recover the intent
owner. The codec never reads Keychain, signs with a user key or calls /exchange.

Independent vectors use official hyperliquid-python-sdk 0.24.0 and msgpack 1.1.2,
with a public disposable private key. Compare action bytes, action hash, EIP-712
digest, signature and reconstructed JSON payload, not only local recovery.

## Acknowledgements

HTTP 200 is not a fill. A single-order acknowledgement must contain exactly one
status. Distinguish an exchange rejection, a complete fill and a partial IOC fill.
Check positive filled size <= requested size, size precision, price bound and a
positive integer order ID. Average execution price may have more precision than
an order price. Resting IOC, contradictory branches, malformed data and unfamiliar
statuses remain uncertain and require orderStatus/userFills reconciliation; never
automatically retry, mark as rejected or credit a balance. An acknowledgement alone
does not update authoritative positions or prove final settlement.
An explicit rejection describes this acknowledgement only; it cannot disprove
a fill from an earlier uncertain attempt. The journal must retain that
distinction and reconcile any previously submitted intent.

## Actual fill reconciliation

Read `userFillsByTime` only for the registered owner and signed order's bounded
time window, with numeric millisecond bounds and `aggregateByTime=false`.
The fixed info transport caps this response at 2 MiB. The API returns at most
2000 rows and exposes only the most recent 10000 fills; a short or empty result
does not establish absence of historical fills. This reader does not claim to
recover data the venue no longer exposes, nor to finish a truncated result.

The encrypted order journal, not a stale UI copy, provides the order identity.
An accepted fill acknowledgement binds its oid; a lost acknowledgement first
needs a terminal orderStatus with matching cloid, coin, side, size, limit and
reduceOnly. Cloids compare as exact 128-bit hexadecimal values, allowing omitted
leading zeroes in API responses. Status recovery preserves evidence even after
wall-clock rollback. No status read, refresh or process restart may resubmit.

Each retained fill must match oid/optional cloid, perpetual coin, side, quantity
precision, price limit, bounded execution time, transaction hash and USDC fee
token. Deduplicate by trade ID; conflicting repeats or a total exceeding known
filled/requested quantity fail rather than overwrite prior evidence. Unrelated
owner fills are never persisted. Eight-fill event batches preserve the existing
16 KiB encrypted-event bound; interrupted batches resume without charging twice.

`fee` already includes builderFee; never add builderFee again. Since initial
signed orders omit builder, a nonzero builderFee contradicts this intent and is
rejected. Negative fees remain rebates. Quantity, notional, fee and rebate sums
use existing exact decimal/rational arithmetic. The displayed weighted average
rounds down to eight decimals; individual fill prices remain unchanged.

Complete quantity coverage requires the deduplicated total to equal the positive
quantity in the acknowledgement (including partial IOC acknowledgements), or
the requested quantity of a recovered filled order. A canceled status and its
remaining-size field do not establish a filled quantity. Until coverage is
proven, the UI shows recorded quantity/fee subtotal and an incomplete state; no
records means unknown actual fees, not zero. These are venue-reported executions,
not a fabricated current position, realized portfolio return or CCTP arrival proof.

After a confirmed submission the signing lease is invalidated before fill reads.
Returned evidence can still be persisted after cancellation/account change, but
cannot appear under the new account. Read-only recovery remains available when
new trading is disabled. The normal confirmation route displays actual fill
details, not fees copied from the earlier quote.

Sources: [Info endpoint](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint),
[fill fields and rebates](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/websocket/subscriptions).

## Account and market observation

`HyperliquidExecutionReader` uses a separate credential-free, bounded, no-redirect
HTTPS transport for fixed /info query types. `HyperliquidTradingSnapshotProvider`
resolves raw metadata and reads userAbstraction, activeAssetData and the target
DEX's positions. Re-read account mode, active leverage and target position at the
end; an observed mode, quantity, side or leverage change invalidates the observation. Queries are not
an atomic chain snapshot. A 15-second wall/monotonic deadline starts before IO;
expiry is also bounded by the position response's server time plus 15 seconds,
including an empty position list. Carry its remaining lifetime into the monotonic
deadline too, so adjusting the wall clock cannot extend an older server response.
Allow at most two seconds of server clock skew;
later/future timestamps, rollback and cancellation cannot refresh old data.

Store actual cross/isolated leverage, signed position size, mark price and each
side's exchange-published maximum size/available-to-trade fields. Do not use a
DEX's withdrawable balance or `spot.total - hold` to infer per-market capacity.
Do not reinterpret availableToTrade as deposit credit, fee-inclusive spendable
cash or borrowing permission. Only USDC-collateral perps are in this funding flow.
Default/standard, deprecated DEX abstraction, unified and portfolio margin modes
remain distinct; observing a mode never changes it.

`checkConstraints` ties the exact order to this wallet, market and snapshot,
requires the leverage/margin mode the user reviewed to match the exchange,
and rejects non-reduce-only size above the venue's side-specific cap. Reduce-only
uses the existing position bound, not an opening-capacity balance: it must actually
reduce an opposite-side position, never grow or flip it, even if opening capacity
is zero. Leverage can
never be silently set to match the paper-trading slider. Constraint success is
not a signing permit or a promise of a fill: fee/price-bound risk, margin-tier/OI
limits, fresh order-book quoting, journal consent and submission remain required.

Sources: Hyperliquid [perpetual account APIs](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint/perpetuals)
and [account modes](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/account-abstraction-modes),
and Alchemy's [active asset endpoint](https://www.alchemy.com/docs/data/hypercore/rest-api/asset-context/active-asset-data)
for buy/sell array ordering, checked 2026-09-11. A third-party SDK currently labels
these arrays min/max; do not sort them or apply that range interpretation.
An additional public read on 2026-09-11 observed a +0.5 `xyz:SNDK` position and
maxTradeSzs `[13951.406, 13952.406]`. The larger second capacity is consistent
with sell-side reduction of a long (difference = twice position size). This
corroborates ordering, not a general collateral/fee formula or atomic snapshot.

## Builder-code frontend boundary

bSmart is a non-custodial trading frontend using Hyperliquid builder codes. It
does not deploy a DEX/HIP-3 market, set venue margin/oracle rules, run matching or
liquidation, or stake to become a market deployer. Existing `xyz` market metadata
is read to select the correct instrument and estimate its venue fee only.

A configured perps builder has a nonzero public recipient address and integer
fee in tenths of a basis point (1 = 0.001%, 10 = 0.01%, maximum 100 = 0.1%).
The immutable order includes this address/rate; the optional action `builder`
map, ordered `b,f`, is part of the MessagePack hash and signed order. No recipient
or production rate is invented. Absence means a no-app-fee protocol intent, not
permission to bypass a future required business configuration.

Read `maxBuilderFee(user,builder)` for the exact owner/recipient before returning
a builder-fee preview. Reject a missing, malformed or insufficient approval;
referral/growth discounts do not reduce the separate app fee. Authorization
must be rechecked immediately before submission. This observation cannot create
an approval or authorize a signature. The owner must explicitly approve a maximum
via the separate user-signed `approveBuilderFee` action, not an agent or the L1
order signing scheme, with revocation and fee changes surfaced in the UI.
Approval signing/consent/submission is still pending; this layer is read-only.

Official builder eligibility currently requires at least 100 USDC perps account
value and standard account mode at the builder recipient. This is not HIP-3
deployer staking, and is not a requirement to switch every user's account mode.
Operations must verify recipient eligibility before enabling production.
Source: [Builder codes](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/builder-codes),
checked 2026-09-11.

## Executable-depth preview

The fixed read transport additionally allows `userFees(user)` and full-precision
`l2Book(coin)`, without price aggregation parameters. A native preview consumes
the exact immutable IOC order and fresh account observation. Decode at most 20
levels on each side; validate coin, time, ordering, positive exact prices/sizes,
lot/tick precision and an uncrossed book. An empty side is not a zero price.

Walk asks for buys and bids for sells, stopping at the order's limit. Preserve
quoted size, uncovered size, notional and levels consumed. Limited depth can
produce a partial preview, never an invented fill beyond the returned book.
Average price and impact relative to the best price use exact BigInt arithmetic;
round only explicit display/estimate outputs. The snapshot's lifetime still
applies, and order-book server time adds a five-second wall/monotonic limit.

Use `userCrossRate` and `activeReferralDiscount` from userFees. Do not reapply the
staking discount already reflected in the user's rate. For USDC collateral, use
the unaligned fee formula: protocol/deployer multiplier `1+s` below scale 1,
otherwise `2*s`; growth mode multiplies by 0.1. Native perps use scale zero.
Existing HIP-3 market metadata must explicitly provide deployerFeeScale; absence cannot mean
free trading. Growth mode accepts enabled/disabled/absent, not unknown values.
Deployer action docs allow scale [0,3] normally or [0,10) under growth; the fees
page contains older narrower prose, so validate against the current action schema.
No staking/linking, referral registration or builder-code authorization occurs.
Preview lists the existing venue fee, optional configured app builder fee and
their sum separately. It assumes no USDC aligned-asset discount; revalidate the
collateral's status before production rollout.

Estimated taker fee is based on observed executable notional, not reserved cash
or a guaranteed maximum. A sell limit bounds price from below, not above; higher
execution prices can increase the fee amount. Quote success cannot authorize a
signature or imply sufficient fee-inclusive collateral. Remaining requirements
include complete margin-tier/open-interest availability validation and final
venue fill/fee reconciliation. Native consent and durable nonce/cloid journaling
are now integrated; the preliminary fee-inclusive capacity check is deliberately
conservative and does not replace venue risk checks or reserve collateral.

Sources: [Info endpoint](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint),
[fee formula](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/fees),
[deployer fee schema](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/hip-3-deployer-actions),
checked 2026-09-11. Book and fee estimates are not fill confirmations.

## Verification

`scripts/generate_hyperliquid_order_vectors.py` generates seven offline vectors;
`--check` regenerates them using the pinned official SDK and compares the fixture.
Its dependencies are verification-only, not added to the backend runtime. The
native tests compare all seven vectors, reject semantic/signature mutations and
exercise precision, metadata and acknowledgement boundaries. Upstream MessagePack
tests run separately. These tests are not production balance/trade acceptance.

2026-09-11: `/tmp/bsmart-execution-protocol-v2.xcresult` reports 65 passing native
tests (23 new protocol tests plus existing wallet/funding/balance/paper regressions).
Upstream MessagePack has 24 passing tests. The five official-SDK vectors regenerate
identically. No device key or exchange submission is involved.

Account observation verification, 2026-09-11: final
`/tmp/bsmart-account-constraints-v3.xcresult` reports 95 passing native tests,
0 failed/skipped, including 26 new tests (25 account/transport/constraint tests
plus current margin metadata), existing order codecs and wallet/funding regressions.
Earlier v1/v2 counts are superseded, not added together. An explicit opt-in
`HyperliquidTradingLiveTests` run passed separately in
`/tmp/bsmart-account-constraints-live.xcresult`. Its retained attachment verifies
the production read transport/provider against public `xyz:NVDA` data, not a
user account, signing permit or real execution. Tests read neither device keys
nor application login credentials. App transaction gates stay disabled.

Builder/depth verification, 2026-09-11: final
`/tmp/bsmart-builder-preview-v2.xcresult` reports 121 passed, zero failed/skipped,
including 26 new arithmetic, fee, depth, preview timing and builder-signature
tests, plus the previous 95 regressions. v1's 120 tests are superseded, not added.
Seven official-SDK vectors regenerate identically. Separately,
`/tmp/bsmart-builder-preview-live.xcresult` has one passed, zero failed/skipped
public-mainnet depth/venue-fee test with a retained attachment. It estimates an
observed order-book level, not a capacity-approved order. No app builder recipient
is configured, and no approval, signing with device keys, or order submission occurs.
The initial full rebuild also surfaced existing Swift concurrency and deprecated
UIKit API warnings outside the changed execution layer; these are not waived
as part of final production acceptance.

## Sources

- Hyperliquid, [Asset IDs](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids), checked 2026-09-11.
- Hyperliquid, [Tick and lot size](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/tick-and-lot-size), checked 2026-09-11.
- Hyperliquid, [Signing](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/signing), checked 2026-09-11.
- Hyperliquid, [Exchange endpoint](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint), checked 2026-09-11.
- Hyperliquid, [official Python SDK 0.24.0](https://pypi.org/project/hyperliquid-python-sdk/0.24.0/), local signing.py and info.py checked against current upstream.
- BatchLabs, [MessagePack writer source](https://github.com/BatchLabs/MessagePack-Swift/blob/c6fabe5afe1261f927a448187b20e84b9af34720/Sources/MessagePack/Writer.swift), revision dated 2020-04-22.
## Native order lifecycle (2026-09-11)

Latest latency revision (2026-09-22): execution info reads prefer a shared native
connection to the official Hyperliquid WebSocket post API, retaining typed decode
and original request/server timestamps. Order-only observations parallelize five
independent reads with a five-second network budget instead of serial repeated
observations within each phase. Independent observations before and after signing
compare exact position (also for openings), mode, leverage, market and non-regressing
server timestamps. They are not atomic exchange snapshots or a collateral
reservation. The original bracketed provider remains unchanged for other users.
No snapshot or balance cache is introduced. A bounded, cooldown-protected HTTP
fallback applies only to public reads, never signed actions. Replies must match
the request ID and query type; rate-limit/server errors are not retried.
The single-slide path uses its immediate unexpired review as the pre-sign proof,
then performs the independent post-sign refresh. Separate review/confirm still
refreshes before signing. Attribution and registry reads overlap; post-sign
registry checks and local revocation checks remain. Mode changes now fail closed.
This supersedes the 31/39 read-count figures below: opening now uses 15/20 info
reads without/with a leverage change. Slow attribution cannot extend review
expiry. This does not claim measured funded execution within five seconds.
Research and acceptance: `docs/operations/trading-latency.md`.

Latency update (2026-09-22): entry and margin preparation overlap fee/account
reads. No-builder previews overlap fees and the book; construction reuses its
own book observation with the original wall/monotonic request timestamps, never
the entry display or a renewed expiry. The same prepared snapshot path avoids
one redundant registry fetch. Confirmation overlaps read-only snapshot refresh
with registry/attribution checks and awaits all results before signing. Post-sign
registry and market checks also overlap; signing and exchange submission remain
ordered and one-shot. Snapshot consistency rounds and all expiry/capacity checks
are unchanged. Unchanged/changed leverage uses 31/39 venue reads, respectively,
plus attribution when applicable; this is not a measured live latency guarantee.
The composer locks immediately after the deliberate slide and shows the actual
stage and elapsed seconds in a stable-height submission control. It never shows
success based on elapsed time. Attribution errors retain bounded machine codes;
missing catalog entries, expired parameters, rate limits and service outages no
longer all become the same error or a wallet-recovery prompt.

Verification: the signed simulator order/preview/snapshot/feed/auth/layout suite
passes 91 tests on 2026-09-22. No funded submission was performed. The initial
unsigned run failed an existing Keychain integration case; the signed rerun
passes that case as well. Real user network/signing/fill latency remains to be
measured after installing this code.

Latency update (2026-09-13): opening via the shared slide reuses the snapshot
obtained within that same operation instead of fetching it twice again. A leverage
change still requires an authoritative read-back. Review validates the reused
snapshot's wallet, market and original expiry. The composer initially selects the
account's actual leverage rather than resetting it to 5x, so an untouched selector
does not request a leverage change. Entry/display data is never order
authority. Independent pre-sign and post-sign refreshes remain, as do fee/depth,
reduce-only, registration, nonce, lease and one-use submission checks. No order
is retried automatically. The unchanged-leverage fixture now performs 32 info
reads rather than 48; this is a request-count measurement, not live fill latency.

Snapshot reads overlap only independent metadata requests or active/position
requests within one round, at most two at once. The two observation rounds remain
ordered and bracketed by account-mode reads. Original server and dual-clock
expiry constraints are unchanged. Progress in the shared composer reflects
checking, leverage update, signing and submission rather than an unlabeled spinner.

Entering or returning to the active trade screen restores only an already bound
wallet. It does not create a wallet, bind an address or place an order implicitly.
Provider/registry failures remain visible and retryable; a missing key still needs
recovery. Legacy local authentication contexts are reused for at most five minutes
in the foreground, scoped by account, with the existing settings and background,
protected-data, sign-out and policy-change invalidation. Signing leases retain
their separate short deadlines; no key bytes are cached by this reuse policy.

Verification (2026-09-13): signed iPhone 16 / iOS 18.5 simulator suite passes
955 tests, 6 skipped, 0 failures. Tests assert 32/40 info reads for unchanged/changed
leverage, two concurrent snapshot reads at most, ordered consistency checks,
automatic restore without creation, and the five-minute authentication boundary.
Two trade-entry UI tests pass, including the missing-wallet -> Google login path.
Generic iOS device build passes without distribution signing. These tests do not
measure funded order latency or verify physical Face ID behavior; no real orders,
wallet creations, account-mode changes or transfers were performed for verification.

Balance integration update (2026-09-12): standard/default-mode balances remain
separate by DEX. A zero-capacity HIP-3 order screen exposes the existing unified
USDC setup with explicit risk confirmation, not an automatic transfer or order.
Only an authoritative unified mode read-back triggers an entry-capacity refresh;
failure remains visible. Display/MAX keep six decimals, and opening inputs expose
the existing 10 USDC notional minimum and fee-inclusive margin limits. No account
equity, spot balance or withdrawable figure is used as substitute order capacity.
Reference: [Hyperliquid account abstraction modes](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/account-abstraction-modes), checked 2026-09-12.

Verification: `/tmp/bsmart-shared-trading-balance.xcresult` passes 38 tests,
including separate/shared capacity refresh, six-decimal small balances, opening
minimums, setup read-back, no automatic signing, existing order safety and six
rendered layouts. No funded transaction or user account-mode change was performed.

UI update (2026-09-12): all live entries use `BSmartTradeSheet` and
`LiveOrderComposer`, including reduction/close. A deliberate slide starts the
existing review/sign/submit pipeline, without a separate intermediate form.
Reduction presets select 25/50/75/100 percent; partial size rounds down to lot
precision and full close preserves the exact position size. The position market
and leverage are fixed, direction comes from the freshly checked signed position,
and `reduceOnly` remains true. No leverage update or Feed attribution is needed
for reduction. Missing positions, invalid percentages and ambiguous submissions
do not become new opening orders. The common modal is above app tabs and keeps
the submission control outside its scrolling contents.

Verification: `/tmp/bsmart-unified-trading-final.xcresult` passes 42 unit/layout
tests and the short-entry wallet-gate UI test. The long-entry/return UI test
initially tapped during chart relayout; after waiting for a hittable action it
passes in `/tmp/bsmart-unified-trading-ui.xcresult`, including the covered-tab
assertion. Six rendered layouts cover light/dark, compact and large text.
The legacy Feed quick-entry UI test remains blocked before order entry: it uses
the old API fixture without a session, while the current Feed requires native
account authentication. Its runtime path is not claimed verified. Architecture,
terminology and diff checks pass. No user wallet or funded order was used.

Native market execution must use a dedicated device-signed IOC lifecycle, never `PaperTradingEngine`. User review fixes owner, coin, side, size, slippage limit, actual leverage/margin mode and fee estimate. The existing encrypted, Keychain-anchored journal records nonce/cloid and each transition before issuing a one-use signing or submission permit. History survives cancellation, sign-out and process restart. Unknown submissions cannot be retried; only read-only reconciliation is available. HTTP 200 alone is not a fill. Partial fills are distinct from complete fills.

Installation boundary (2026-09-22): the container marker selects the journal's
Keychain namespace; existing databases retain their legacy anchor. A fresh
container (no marker and no database), including legacy orphan-anchor migration,
starts a separate ledger and preserves every previous anchor. Lost local history
is not recovered, reconciled or replayed by this operation. All new orders still
require explicit intent, fresh venue positions and nonce allocation; closes remain
reduce-only. Missing/corrupt storage within a marked installation continues to
block submission rather than silently resetting. Local journal errors are not
reported as market-price changes. Wallet identity/keys are never reset.

Validation: `/tmp/bsmart-close-journal-device-final.xcresult` passed 62 tests on
iPhone 15 / iOS 26.2.1, including an opt-in installed-container check of journal
reads, nonce allocation, reopening and unchanged legacy anchor bytes. The original
failure was reproduced before the fix: legacy checkpoint sequence 80, no database,
integrity error. `/tmp/bsmart-close-journal-extra-simulator-final.xcresult` passed
60 additional test executions covering installation, integrity, signatures,
funding consent, withdrawals and account setup (installation cases overlap the
device suite). Mock-venue reduction preserves 0.018 size, reduce-only and single
submission. No funded trade, withdrawal or deposit was executed. Earlier runs
were superseded after the concurrent-read test fixture was corrected; attempted
extra runs also encountered a shared build lock and a missing device test bundle.

Stored market metadata is an archive, not authority: fresh raw metadata and account checks must match before signing/submission. Signed bytes and responses are persisted even if the UI task was cancelled. Basic execution remains subject to the existing identity/recovery/production capability gates; absence of builder configuration is not a gate.

`LiveMarketOrderView` replaces the paper order route and Feed shortcut execution.
The user reviews notional, direction, exact size/price limit, current leverage and
estimated fees, then explicitly confirms. App-account balances no longer display
paper equity or positions. The production trading capability stays closed.

Local regression: `/tmp/bsmart-basic-execution-v3.xcresult` has 110 passing tests,
zero failures/skips; it includes three real vault-adapter tests using public
disposable entropy and a test Keychain, not user funds. Three UI cases passed in
`/tmp/bsmart-basic-execution-ui-v2.xcresult`. These are not funded execution tests.
The withdrawal codec matches three independent eth-account EIP-712 vectors; its
fee-reader tests cover contract/chain changes, pause, reorg and both clock limits.

Withdrawal journal verification: `/tmp/bsmart-withdrawal-journal-final.xcresult`
contains 102 passed, zero failed/skipped tests, including 25 new lifecycle/owner
nonce tests plus existing funding/order regressions. Tests cover concurrent journal
instances, encrypted signature persistence, cancellation, process restart, clock
rollback, one-way submission states and old order replay. They use public test keys
only. The preceding 98/100-test runs are superseded, not additive. No protected
withdrawal signer, broadcaster or funded destination receipt is claimed by this run.

### Pre-sign expiry during opinion attribution (2026-09-22)

A same-slide preview may expire while authenticated opinion attribution or wallet
registration is awaiting the network. Before any journal reservation or signature,
only typed account/quote staleness triggers one fresh snapshot and quote for the
exact original order. This does not recreate its cloid, nonce, expiry, side, size
or limit. Existing position, mode, leverage, fee and capacity checks still apply.
Manual review/confirm and all post-sign paths do not gain this retry. Network,
invalid response, leverage and capacity failures are not retryable through this path.
Typed failures have distinct localized messages and non-sensitive OrderLatency codes.

Validation: simulator build and 49 native regressions passed, including a 6-second
attribution delay that still submits exactly the registered intent once, rejection
after a changed account mode or expired 60-second intent, and existing post-sign,
capacity, leverage and dual-clock expiry tests. No live trade was performed; the
screenshot alone cannot identify the original typed failure on that device.

### Inline close-position entry (2026-09-22)

The ordinary instrument composer exposes a segmented open/close selector when its
verified entry snapshot contains a position in that exact market. Existing position
entry points still start in close mode. Switching resets the amount (100% close,
zero opening margin) and invalidates any old preview; no switch while submitting.
The existing 25/50/75/100 presets and integer 1–100 input use executeReduction.
Missing positions disable close submission without silently changing to opening.
