# Equity Routing

Status: discovery, previews, pre-execution intent persistence and P4 funding preflight, 2026-10-01. Not funded execution or App rollout.

## Signing Exposure Phase P5c

OpenAPI v0.5.1 adds an internal `EquitySigningPayload` schema, not an HTTP path.
`beginPreparedSigning` rechecks the private immutable order against current owner,
intent/version, HL/issuer, spendable balance/allowance/rebase and original quote
freshness. Only then may the service-only `bsmart_equity_signing_start` RPC persist
`reserved -> signing` before any material is returned. Identical fresh retries
restore the same order and original signing timestamp, never a replacement quote.
Failure/lost response after the write retains the held signing state. A rejected
wallet prompt, expiry or absence of a signature is not proof of no signed order.

Migration `202610010007_equity_signing_exposure.sql` includes signing in the wallet
unique index, cross-withdrawal guards and parent mutation guard. Only untouched
reserved preparations may cancel/release. Signing can advance only to authorized;
direct signing-to-release, quote refresh and expiry-based release are forbidden.
Authorization cannot skip signing-start; parent version advances only on accepted
consent. Legacy authorized rows may lack a signing timestamp but cannot be renewed.
Uncertain signing release still requires future provider/chain reconciliation.

Native `Core/Trading/Equities/EquityCowSigningPayload` rejects unknown nested fields.
`Core/Wallet/EquityCowOrderCodec` constructs only the fixed production CoW Order
schema, verifies reviewed account/owner/intent/asset/amounts/expiry and reproduces
SDK digest and UID with existing WalletCore. BigUInt preserves uint256 amounts.
Only Ethereum/Ink raw-token, 1x, already-funded USDC buys are supported; sells
remain blocked without bounded return consent. Signature verification reuses the
existing strict low-S owner recovery, not eth_sign or a generic signing request.
The codec contains no private-key access, networking or wallet invocation.

Public disposable key-1 vectors cover both chains and an amount above UInt64.
They prove byte compatibility, not funded quotes or execution. No native UI/store,
public signing API, sponsor, fund/return authorization or submit worker is enabled.
Both signing HTTP and real execution remain closed independently of the migration.

## Preparation And Reservation Phase P5b

OpenAPI v0.5.0 introduced authenticated `POST /intents/{id}/prepare`, accepting only
`{expectedVersion}`. `BSMART_EQUITIES_PREPARATION_ENABLED` defaults false and
requires preview/ledger dependencies and migration `202610010006`. It refreshes
quotes, restricts candidates to provider-verified, already funded and approved
orders, compares minimum net outputs using actual decimals, then atomically
persists the selected public preview, private canonical material and preparation.
No client-selected chain, provider payload or signature is accepted. One selected
candidate is saved; expiry of unselected alternatives cannot invalidate it.

Preparation consumes a quoted version (or a draft) and increments the intent
version exactly once. Immutable private rows contain normalized order/domain,
UID, quote fingerprint and a jsonb-order-independent SHA256. Identical retry with
the old/current version returns the same preparation, without requoting. A
different body, changed wallet or cancelled preparation cannot replace it.
UID uniqueness is permanent across intents, not only within an HTTP request.

The private table is RLS-enabled, has no authenticated/anon read or mutation
grants, and permits only service reads and security-definer RPC writes. The
response contains only identifiers/network/expiry and `state=reserved`,
`reservationsImplemented=true`, `signingEnabled=false`, `executionEnabled=false`.
The intent remains `quoted`, but refresh is frozen until explicit cancellation;
cancellation releases a reserved preparation atomically. Expiry alone never
releases any reserved, signing or authorized preparation. After P5c exposure,
signing preparations cannot use this pre-sign cancellation path.

Wallet-wide triggers share the original withdrawal advisory key with both old
withdrawal tables, including direct service-role state updates. They check all
active equity/withdrawal records, rather than just equity. New guards use try-lock
and fail closed on contention to avoid deadlocks with legacy wallet-first reserve
and row-first update callers. This serializes known coordinated flows only: it
cannot prevent independent wallet/device/HL trading or incoming deposits, and is
not an onchain escrow or a fungible balance accounting system.

`authorizePreparedIntent` is internal-only and now requires persisted signing
exposure. It rereads bound owner, intent,
issuer/HL status, balance/allowance/rebase and verifies EIP-712 before a service
RPC installs consent and one permanent order leg atomically. SQL is a CAS boundary,
not a signature verifier. Identical accepted consent can be recovered after
expiry without fresh permission; altered consent cannot replace it. Sells are
blocked at authorization until bounded return consent is implemented. The leg
remains reserved with attempts=0, parent state=authorized. A database trigger
blocks all leg execution independently of HTTP flags. No signing/authorize/submit
HTTP endpoint, worker, bridge consent, approval sponsor or HL credit is enabled.

The older P4 funding-preview still has no funding-leg reservation/consent and
returns its existing false implementation flags. It can include preparation
reservations in read-only activity checks when the preparation gate is enabled.

## V1 Execution Policy (Planned)

Confirmed product policy: sell proceeds default to the user's HL perpetual account.
This is a separate funding leg after a chain-confirmed spot sale, not an atomic
rollback or immediately available HL margin. Quote and authorize its fee cap and
recipient; retain a recoverable `return_pending` state until HL credit is verified.
Failure leaves identifiable user-owned USDC, never a fabricated HL balance. No
return transfer is implemented or activated by the research tooling below.

V1 now targets 30-50 high-interest assets with verified HL absence, rather than
the earlier five-instrument proposal. Use a complete issuer registry and the
product's sampled one-year X discussion counts as an explicit popularity proxy,
not a claim of the globally most traded assets. Preserve a ranked target list
separately from current quote availability and execution eligibility. Daily-reset
leveraged/inverse ETFs need a separate product/risk model and do not pad this list.
Public CoW orders on an EVM chain are the preferred execution investigation;
direct issuer xChange onboarding is not a V1 dependency. Existing Solana-only
`/route` and `/preview` remain unchanged and disabled for execution.

Trading stays open 24/7 when an executable route exists. Weekend depth is a soft
selection factor, not a requirement for weekday-equivalent $10,000 execution.
Keep minimum receipt, issuer identity/halt checks and owned-token sell limits.
Missing weekend observations are `untested`, not evidence of liquidity. Public
issuer trading-hours metadata describes its primary market and must not by itself
close secondary trading; genuine issuer halts remain blocking.

`scripts/screen_xstocks.ts` (inside the iOS account project) performs unsigned
public quotes only. It checks the complete HL catalog before and after screening,
uses issuer-provided EVM token and USDC addresses, and records both quote legs,
fee-inclusive raw units and verification flags. Quote-only synthetic accounts
have no balance/allowance proof. Quote round-trip difference includes fees, spread
and price changes between requests; it is not realized P&L or an execution test,
and excludes funding/return and first-approval gas costs. No report enables trading.

`scripts/select_xstocks_candidates.ts` consumes a complete dated registry and
aggregated, non-identifying popularity evidence, rechecks the current HL catalog,
rejects duplicate identities and invalid metrics, and exports a bounded ranked
research list. Its files are not a runtime venue-selection or signing authority.

## Priority

### EVM Discovery Phase P1

P3 persistence and snapshot details are recorded below; P1 discovery checks still
apply when its registry is supplied by Storage rather than pagination.

`bsmart-equities/route?ticker=...` is the new independent EVM discovery contract
(`contracts/openapi/supabase-equities.yaml`). It reuses the complete HL reader and
priority policy; the existing Solana `bsmart-markets` API remains compatible.
`BSMART_EQUITIES_DISCOVERY_ENABLED` defaults false and enables only authenticated
read-only discovery, never signing or execution. Unknown query fields, user token
addresses, network selections and mutation requests are rejected.

After fresh verified HL absence, a fixed 50-name discovery inventory permits an
unfiltered complete issuer registry lookup. USD identities, symbols and per-chain
raw/wrapper addresses must be unique. Registry TTL is ten minutes, current asset
details and HL TTL thirty seconds. Detail re-read must preserve ID, symbol,
underlying and deployment identities; current halts block. Slow discovery refreshes
HL before returning an xStocks route. Failed reads return sanitized 503 errors.

Responses preserve raw HL market identity or enumerate official raw Ethereum/Ink
instruments with native USDC addresses. No best chain is selected from historical
quotes. `status=available` means metadata discovery only: `executionEnabled=false`
and `gasCoverage=unverified` are unconditional. No CoW quote, share conversion,
balance, allowance, signing payload, transaction or funded fill is returned.
`defaultSaleProceedsDestination=hyperliquid_perps` records product policy, not an
implemented transfer. Existing positions are not rerouted by this endpoint.

Implementation phases and service reuse are tracked in
`docs/operations/xstocks-infrastructure-plan.md`.

### Intent Ledger And Catalog Snapshot Phase P3

OpenAPI v0.3.0 adds authenticated `POST /intents`, `GET /intents/{id}` and
`POST /intents/{id}/{preview|cancel}`. The independent
`BSMART_EQUITIES_LEDGER_ENABLED` gate defaults false. Create accepts only
`{clientIntentId, input: PreviewRequest}`; owner comes from the existing server
wallet binding. No provider call or money movement is required to persist a draft.

The client ID is unique per account. A stable SHA256 binds account, owner and all
input/fee/minimum constraints; different owner, hash or JSON content reusing the
same ID returns 409. Exact retries recover the original record, including cancelled
records. At most 20 unfinished intents per account; cancel unused drafts.

Preview refresh accepts only `expectedVersion`, derives saved immutable input and
checks owner again. A row-locked CAS saves the non-executable preview, checks its
remaining TTL and increments version. Concurrent cancellation/refresh rejects a
late quote; recover with GET rather than guessing the result. A saved preview is
not user authorization. Quote expiry stays explicit; only draft/quoted can refresh.
Cancel is pre-execution only, with exact retry returning the same cancelled record.
It remains available when the wallet is unavailable; it cannot reverse a fill or
bridge. Reads return own intent and safe leg summaries, not lease credentials,
evidence hashes or provider raw bodies. SQL RLS and column grants also protect
direct authenticated reads. Only service RPCs mutate; table write grants are absent.

Legs reserve provider ID, source/destination network and request hash before a
future submission. `(intent, kind, legIndex)` permits two distinct funding/return
segments; provider IDs are unique within provider/source network. Dependent legs
require confirmation. Each can claim one permanent attempt and 60-second lease.
Lost claim responses, crashes, timeouts and lease expiry never allow resubmission:
reconcile the pre-reserved provider ID or receipt. Unknown is not failed; terminal
observations require a hash from a future verified adapter, not a guessed status.
The hash itself does not prove fill or HL credit.

P3 exposes no authorization/leg insertion RPC or HTTP executor. Only draft,
quoted and cancelled are currently API-reachable; execution states await P4/P5
verified transitions. Service-only claim/observe primitives cannot act without
separately installed authorized legs. Reconciliation/authorization/approval/
funding/fill/return workers remain unimplemented; migration does not enable them.

`BSMART_EQUITIES_CATALOG_SNAPSHOT_ENABLED` independently selects private
`bsmart-equity-catalog` Storage instead of user-time pagination. The publisher
validates the complete unfiltered registry, then compacts EVM identity fields and
keeps non-USD identities, not a 50-name subset or liquidity/eligibility decision.
`active.json` contains exactly `schema=1, sha256, observedAt, nodeCount, assetCount`;
immutable `<sha256>.json` contains `schema=1, at, nodes`. Hash, byte limit (4 MiB),
unique identities, counts and original collection time are revalidated. Content
never overwrites; pointer updates only after readback. Use one trusted publisher.

TTL is ten minutes, also on memory hits; pointer checks coalesce and cache for
at most 15 seconds. Reusing a hash cannot renew time. Failure/expiry blocks, with
no silent paging/stale fallback. HL/live details retain 30-second checks. Hashes
detect integrity drift, not provenance: private bucket writes stay restricted
to the trusted publisher/service role. Reuse existing
[Storage access control](https://supabase.com/docs/guides/storage/security/access-control),
not a new cache server. Future recovery uses the
[CoW order status API](https://docs.cow.fi/cow-protocol/integrate/api); no such
execution worker is enabled by P3.

### Funding Preflight Phase P4

OpenAPI v0.4.0 adds `POST /intents/{id}/funding-preview` with only
`{expectedVersion}`. The independent `BSMART_EQUITIES_FUNDING_PREVIEW_ENABLED`
gate defaults false. A fresh saved quoted intent, immutable owner and current
version are required. The endpoint does not refresh or write the intent, reserve
funds, create legs, sign, approve or submit. It checks the row/version/wallet
again after provider reads; concurrent cancellation or wallet changes reject it.
Empty plans plus per-chain failures are valid diagnostics, not success to trade.

Buy plans use execution-chain on-chain USDC first. Pending bridge estimates are
never added. Only a deficit requests an independent HC withdrawal quote. Classic
accounts use `withdrawable`, not `accountValue`. Unified accounts require all
perp venues free of positions/orders, zero USDC hold, stable full venue directory
and abstraction mode; perps and shared spot are never summed. Portfolio margin
is unsupported for funding (existing execution-chain USDC still works). Source
and destination balances/multiplier are re-read, mode changes or decreases in
available HC funds block. These observations are not an atomic lock or guarantee
against future external activity; P5 needs wallet-wide reservations and rechecks.

Wallet-wide active records in existing withdrawals/Across/equity ledgers block
before and after planning. Unknown/expired-inflight records are not assumed paid
or failed. Incoming Relay estimates and provider success are not credit evidence.
The guard exposes no other-account record detail, cannot see every device-local
or external transaction, and cannot replace the future transactional reservation.

The new Relay adapter requests exact-input `/quote/v2` with same owner/refund,
protocol v2, no deposit-address registration, no top-up, zero bridge slippage and
no fee subsidy. It checks currency identity, decimals, input/output protocol
payments, owner refunds, empty custom calls, deadlines and safe step summaries.
HC v2 nonce mapping and EVM USDC permit shapes are diagnostics, not fully decoded
signing permission. Permit recipient can be an execution router rather than the
depository: P5 must verify its trusted deployment, complete typed message and
post body. `permit_executor_unverified` remains a blocker. No provider signing
payload, nonce, raw body, execution URL or request ID leaves the API.

Amounts use integers: HC source cost rounds up from 8 to 6 decimals, guaranteed
receipts round down. Buy HC input is bounded by the deficit plus the remaining
user network-cost ceiling after CoW network cost, and available withdrawable
funds. Minimum bridge receipt must cover the deficit. Any excess stays user-owned
USDC, not an invented fee. Buy cost scope is CoW quoted network cost plus worst
bridge input-minus-minimum-output loss; nested Relay fee totals are not added
twice. Sell scope is bridge loss only, because CoW sell network cost is in stock
token units and already bounded separately. This read-only ceiling is not user
funding consent, and excludes approval/native gas, dynamic protocol costs and
unverified sponsorship. Native-gas routes block rather than require gas from users.

Sell preflight requests return to the same owner's HC perps based only on the
CoW quoted minimum USDC proceeds, not an existing wallet balance. It is hypothetical
until actual settled proceeds are proved. P5 must obtain a fresh return quote and
bounded consent after fill; the pre-sale quote is never reused to move funds.
`returnTransferImplemented=false`, `reservationsImplemented=false`,
`executionEnabled=false` and `gasCoverage=unverified` are unconditional.

Relay's [HC integration](https://docs.relay.link/references/api/api_guides/hyperliquid-support)
supports direct bidirectional routing and requires v2 nonce mapping for withdrawals.
The [quote API](https://docs.relay.link/references/api/get-quote-v2) describes permit,
deadline and refund options. Actual route availability and fees still require
live validation. Across's existing Arbitrum withdrawal executor is unchanged;
generalized Across funding/second-segment fallback and credit reconciliation are
not implemented by this preflight, and no fallback is silently invented.

### EVM Quote Preview Phase P2

`POST bsmart-equities/preview` is independently gated by
`BSMART_EQUITIES_PREVIEW_ENABLED` (default false). Its JSON contract is in
`contracts/openapi/supabase-equities.yaml` (preview introduced in v0.2.0). Requests contain only ticker,
buy/sell side, decimal amount, explicit slippage/network-fee ceilings and an
optional stronger output floor. Unknown fields/query parameters are rejected;
the body is limited to 4096 bytes. The authenticated account's `bsmart_wallets`
binding supplies both CoW `from` and `receiver`. No owner, chain, token, calldata,
appData, signature or partial-fill choice may come from the client.

Buy previews preserve P1 HL priority, both before and after provider reads.
Sell previews instead resolve the original official EVM token and verify its
adjusted on-chain balance. New HL listings and the buy discovery inventory do not
strand existing xStocks holdings. Issuer halts/identity failures still block exits;
there is no short selling or synthetic owned balance. Candidate chains remain
server-evaluated, not a new chain selector in the App.

Viem 2.56.3 reads chain ID and one block's decimals, balanceOf, CoW-relayer allowance,
getCurrentMultiplier and pending activation time. Balances and multiplier are
read again after quoting, with a 30-second observation TTL and maximum 120-second
block age. Reject rebase changes and the issuer-recommended +/-15-minute activation
window, including the planned five-minute order lifetime. On EVM, balanceOf already
includes the multiplier: do not multiply again or transact using sharesOf units.
Input/output conversion is exact; excess fractional precision is rejected, not
rounded. Here `Raw` means ERC20 atoms, not immutable internal share units.

The fixed public CoW quote endpoint uses a bounded eight-second, 2 MiB JSON
transport, with no quote retry, signer or order submission. The pinned official
SDK modules (`sdk-order-book` 4.2.1, `sdk-order-signing` 1.1.15 and `sdk-config`
2.7.2) supply types, fee/slippage math, domain and relayer addresses. The SDK HTTP
client has no injectable AbortSignal, so the existing bounded REST transport is
retained rather than mutating global fetch. SDK modern order math includes quoted
network cost in normalized sellAmount and sets the normalized order feeAmount to
zero; do not sign the unmodified fee-bearing quote. SDK imports need Deno's
`nodeModulesDir=auto` for the transitive cross-fetch/polyfill package.

Validate quote owner/receiver, exact pair, fee-inclusive budget, positive uint256
amounts, five-minute validTo, fee expiration, sell kind, nonpartial fill, erc20
balance modes and the fixed zero appData (no hooks/partner fee). Normalize only
known order fields; provider-supplied domains or signing JSON are never forwarded.
The network-fee ceiling is only an indicative network-cost cap, not a ceiling for
bridge/approval or every dynamic protocol fee. `minimumOutputAmountRaw` binds the
quoted net output after slippage and any stronger requested floor.

Responses contain candidates and sanitized per-chain failures, exact amounts,
balance/allowance observations, provider verification and blockers. The SHA256
fingerprint binds account, instrument, constraints, quote economics, normalized
SDK order/domain, expiry and chain observation. It is not a signature, reservation,
authorization token or order UID. No public signing payload exists yet. Even a
verified quote with sufficient balance/allowance stays `executable=false` until
the durable ledger, fresh signing checks and sponsorship are implemented.
Return-to-HL is policy only: `returnTransferImplemented=false`.

References: [CoW API](https://docs.cow.fi/cow-protocol/integrate/api),
[official SDK](https://docs.cow.fi/cow-protocol/integrate/sdk),
[xStocks EVM multiplier semantics](https://docs.xstocks.fi/developers/multipliers).

### Internal CoW Preparation And Evidence (P5a)

OpenAPI v0.4.1 adds internal `CowPreparedOrder` and
`CowReconciliationObservation` schemas only. Current HTTP routes neither return
canonical signing data nor accept signatures or order submission. No new flag
enables these functions, and observations do not mutate the ledger.

`validateQuoteArtifacts/previewEquityArtifacts` keep private canonical material
beside the unchanged public preview, not reconstructed from a fingerprint later.
Field ordering is fixed before hashing to survive a future jsonb round trip.
`prepareCowOrder` consumes server-produced material, saved candidate, current
server wallet binding, version and fresh chain state. It requires a simulated
quote, sufficient balance/allowance and unchanged multiplier/nonce. Buy routing
and issuer status must still be rechecked by a future authorization orchestrator.
The private result is neither consent nor a reservation and is not yet persisted.

Official pinned CoW signing/contracts SDK with the official viem adapter produces
the EIP-712 domain/types/digest/UID. No production signer exists in this codec.
V1 accepts EOA EIP-712 only: exact owner/receiver, pair, fee-inclusive input,
minimum output, production settlement, zero appData/static fee, sell kind and
nonpartial ERC20 modes. `verifyCowSignature` is crypto verification alone;
`verifyBoundCowSignature` additionally repeats intent/material/current-wallet and
balance checks after signing. Neither starts execution. The authorization
transaction and iOS-specific validator remain prerequisites. Multiple intents
can share one UID; retain the permanent `(provider, source_network, provider_id)`
uniqueness constraint when installing legs.

`reconcileCowOrder` checks the original UID even after expiry using bounded CoW
GETs and read-only viem RPC. Provider `fulfilled` needs matching order/trade and
finalized canonical receipt, a unique official settlement Trade plus exact net
input/output ERC20 transfers for the owner. Missing/reorg/partial/duplicate or
ambiguous multi-order batches never become credit. A missing, cancelled or
expired API order is not proof of no chain execution and never releases funds.
Finalization delays must be measured separately from API fill latency; there is
no downgrade to latest blocks when finalized reads are unavailable.

Only confirmed sells expose the actual net `saleProceedsUsdcRaw`; this does not
prove those funds remain unspent. Fresh balance, return quote, bounded owner
consent, gas and HL credit proof remain necessary. `returnReady` and
`resubmitAllowed` are always false, including confirmed observations. The
`evm-equity-cow-codec.json` fixture is entirely synthetic and has no signatures.

Sources: [official CoW SDK](https://docs.cow.fi/cow-protocol/integrate/sdk),
[order and trade API](https://docs.cow.fi/cow-protocol/integrate/api),
[settlement events and transfers](https://github.com/cowprotocol/contracts/blob/main/src/contracts/GPv2Settlement.sol).

### Legacy Solana Discovery

`bsmart-markets/route?ticker=...` verifies the full current Hyperliquid perpetual
catalog first. Prefer `xyz`, then another exact-symbol USDC market, with stable
coin ordering as a tie-break. Return the original DEX/coin, never a computed asset
ID. The existing HL execution adapter must still resolve fresh raw indices before
signing. An active non-USDC market blocks fallback rather than implying no market.
Delisted markets do not accept new orders. Partial, malformed, expired or failed
HL observations return 503, never permission to use xStocks.

Only verified absence of an active HL market permits xStocks lookup. The issuer's
complete, paginated public registry supplies underlying ticker, USD currency,
asset ID and exact Solana mint; do not infer a mint from a ticker or accept a
client-provided mint. Duplicate underlying identities or Solana deployments fail
closed. Halted assets return a blocked route. Missing deployments return unsupported.
Complete issuer identity registries may be coalesced/cached for at most ten minutes;
reads are bounded to 100 pages / 10,000 records / a 90-second iteration deadline.
Each selected Solana asset is independently re-read by its registered symbol and
must preserve asset ID, underlying ticker and mint. Its current halt status and the
HL observation must be less than 30 seconds old. Slow registry discovery refreshes
HL once before returning an xStocks route; newly listed HL markets still win.
An expired identity registry or failed detail read never permits fallback.

Routing is for new order discovery only. Existing positions always retain their
venue and instrument identity. Selling xStocks never opens a short; it consumes
verified owned tokens. Spot is 1x and long-only. HL holdings cannot be closed on
xStocks, or vice versa. Provider errors and liquidity are not venue-switch triggers.

## Read-only quote

`GET /preview?ticker=...&amountUSDC=...` accepts positive decimal USDC with at
most six fractional digits, up to 100,000 USDC. Only an available xStocks route
uses Jupiter Swap V2 `/order`, without `taker` or `payer`. Return the exact input
and raw output token units, router, and observation time. No request ID,
transaction, signature, wallet, fee payer or arbitrary provider URL is exposed.
`executable=false` and `gasCoverage=unverified` are unconditional. This is an
indicative buy quote, not a balance check, guaranteed fill, share quantity, net
USDC debit or gasless quote. Scaled UI multipliers and chain decimals must be
applied before any future holdings/share-price display.

Both endpoints require server-verified non-anonymous Apple/Google Supabase Auth.
No-store responses use fixed machine error codes; no provider bodies or credentials
are logged. Only authenticated valid inputs reach public providers. No mutation,
signing or submission endpoint exists in this phase. The preview gate defaults off.

## Activation Requirements

- Server-only `BSMART_JUPITER_API_KEY` and `BSMART_XSTOCKS_PREVIEW_ENABLED=true`
  enable indicative previews only; neither setting enables execution.
- User-owned Solana wallet linked to the existing Supabase UUID with independent
  ownership proof; no replacement of the funded EVM wallet or mnemonic reuse.
- Native Solana signing plus decoded transaction validation, mint/program/account
  allowlists, exact-input/min-output bounds and fresh blockhash/quote expiry.
- Durable intent, one-shot submission and chain-confirmed receipt reconciliation;
  uncertain submissions are queried, never rebuilt or automatically resubmitted.
- Native Solana USDC balance or a separately authorized funding route. Never
  count the same in-flight USDC on two venues or treat HL margin as available cash.
- Gas sponsor or actually verified gasless provider quote. Costs still exist;
  user-visible USDC fees and app-funded gas budgets require bounded consent.
- Provider eligibility restrictions and issuer asset lifecycle checks remain
  prerequisites, independent of the token's permissionless transfer capability.

Sources checked 2026-10-01: [HL perpetual metadata](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint/perpetuals),
[issuer asset registry](https://docs.xstocks.fi/apis/openapi/assets/list_public_assets),
[Jupiter V2](https://dev.jup.ag/docs/swap/order-and-execute),
[xStocks developer guide](https://docs.xstocks.fi/developers).
