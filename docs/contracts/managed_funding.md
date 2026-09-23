# Managed perpetuals deposits

Decision: 2026-09-22. Use the existing Privy owner wallet and Relay Deposit Addresses.
The destination is HyperCore USDC (Perps), not HyperEVM, spot, or an intermediate
Arbitrum balance. No bSmart sweep worker, delegated server signer, new bridge
contract, private-key custody, or funding database is required.

## Provider boundary

`bsmart-funding` authenticates the existing Supabase session and resolves the
immutable `bsmart_wallets` binding. Clients cannot select a recipient or refund
address. Relay receives that bound owner as both recipient and source-chain refund
address. Native USDC on Arbitrum, Monad, Base, or Ethereum, and Binance-Peg
USDC (BEP-20, 18 decimals) on BNB Chain are offered. Refunds can
return to that owner's source-chain wallet; they are not perpetual buying power.
Robinhood Chain is not offered because Relay's current source-currency catalog
does not list USDC for that chain, even though the chain accepts deposits.

`POST /address` accepts only `{network: "arbitrum" | "monad" | "base" | "ethereum" | "bnb"}`. It registers a
reusable open address with `strict: false`. Relay requires a seed quote; the server
uses 20 USDC solely to validate/register the route. This is not a requested payment,
minimum deposit or arrival estimate, and it is never returned as user-facing data.
The response contains network, recipient, refundAddress, depositAddress, reusable
and createdAt. Every actual deposit is requoted by Relay on receipt. Tiny deposits
may be refunded minus gas when they cannot cover execution costs.

The iOS screen loads the address automatically after network selection; it has no
amount field or estimated-arrival row. It hides mismatched-network addresses
immediately and invalidates in-flight responses on account/network changes.
Fee information is available in a disclosure, including the one-time HyperCore
activation fee for new accounts. No fee sponsorship has been enabled.

`POST /quote` remains backward-compatible for older clients. It accepts
`{network: "arbitrum" | "monad" | "base" | "ethereum" | "bnb", amount: "100"}` and calls
Relay `/quote/v2` with an open deposit address, EXACT_INPUT, 50 bps slippage,
HyperCore chain identifier 1337 and its provider-specific perps USDC identifier.
Relay identifiers/decimals are provider metadata, not Ethereum chain IDs or
Hyperliquid ledger precision. The response is validated before exposing its QR.
Quotes are indicative for open addresses: each actual deposit is requoted.
Monad uses chain ID 143 and Circle native USDC
`0x754704Bc059F8C67012fEd69BC8A327a5aafb603`; the direct Hyperliquid Monad
deposit address only accepts MON and must never be shown as a USDC address.
Ethereum uses Circle native USDC at
`0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48` (6 decimals). BNB Chain
uses Binance-Peg USDC at `0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d`
(18 decimals), not Circle native USDC. The server scales and validates each
source amount using its own token precision before returning a deposit address.

`GET /` returns `{available}`. `GET /deposits` proxies `/requests/v3` filtered by
the verified recipient and HyperCore destination; validates each returned owner
and destination currency, and exposes at most 20 recent deposits. This provider
history survives reinstall and accounts for repeat use of an open deposit address.
Unknown states never become success. Provider success is shown as delivered;
existing Hyperliquid account-mode-aware balance checks still determine trading
availability. Failed history reads do not become an empty successful result.

Enable only with `BSMART_DEPOSITS_ENABLED=true`,
`BSMART_RELAY_FUNDING_ENABLED=true`, and server-only `BSMART_RELAY_API_KEY`.
No credentials in Swift. No migration. No broadcast or funding operation is
performed by the proxy; routing, execution, retries and refunds belong to Relay.

Existing wallet balances and already submitted CCTP transfers remain accessible
through the legacy wallet transfer/history flow. Receiving at a previously copied
owner address does not automatically route funds. New deposits must use the
provider-issued deposit address. No server sweep is silently enabled.

## Verified sources

- https://docs.relay.link/features/deposit-addresses
- https://docs.relay.link/references/api/api_guides/hyperliquid-support
- https://docs.relay.link/references/api/get-requests
- https://docs.privy.io/wallets/funding/crypto-deposits/overview
- https://docs.privy.io/wallets/actions/swap/overview
- https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/usdc

Privy native crypto deposit docs currently list EVM/Solana destinations, with no
documented HyperCore perps destination. Privy's Hyperliquid recipe still shows the
deprecated Bridge2 example; it must not supersede Hyperliquid's current CCTP docs.
Relay's public chains and quote endpoints were checked without sending funds.
Production requests history requires an API key in the observed response.
Fiat/card onramps need a separately configured provider and are not implied by
this crypto deposit integration. External wallet/exchange sending fees remain
the sender's responsibility; embedded bridging fees are included in Relay quotes.
