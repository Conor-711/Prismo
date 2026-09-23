# Privy + Relay managed funding

## Architecture decision (2026-09-22)

Keep the existing Privy user wallet and Hyperliquid perpetual order execution.
Use Relay's managed deposit addresses to fill HyperCore USDC (Perps) directly.
bSmart's Supabase function verifies identity, fixes the recipient and validates
provider responses; it neither signs nor moves funds. No watcher, relayer, custom
bridge, delegated Privy signer, cron job or funding schema is deployed.

Privy Crypto Deposits is a real managed product but its documented swap routes
currently do not include HyperCore perps. Privy's Hyperliquid quickstart references
Bridge2, which Hyperliquid's own USDC page marks deprecated. Do not copy this older
example into new deposits. Relay documents HyperCore perps support separately from
HyperEVM and spot. The live chains API confirmed destination 1337, perps USDC
identifier `0x00000000000000000000000000000000`, and 8 provider decimal places.
These are Relay identifiers, not an EVM chain or the ledger's native USDC precision.

## External configuration

Deployment status, 2026-09-22: `bsmart-funding` is deployed to the existing iOS
account project `dzyitinagewdfkzjkuiz`. The Relay key is stored in Edge Secrets and
both funding flags are enabled. Live provider checks passed for 20 USDC quotes on
Arbitrum and Base with the production parser, plus requests-v3 history. These
used a non-funded verification address, not a user's authenticated app session.
Unauthenticated production requests return 401. The temporary credential-protected
verification function was deleted and its endpoint confirmed 404. No funds were
sent; actual delivery, refunds, restart and account switching still need acceptance
in the new iOS build. The project version is now 1.0 (8); upload is a separate step.

2026-09-23: Monad native USDC (chain 143, Circle contract
`0x754704Bc059F8C67012fEd69BC8A327a5aafb603`) is added to the same Relay
managed-address route. A public Relay quote returned an open address and HyperCore
perps USDC output for this route. This is quote verification, not a completed
mainnet transfer. Hyperliquid's direct Monad deposit address accepts MON only.
The isolated `bsmart-funding` deployment is version 4 and ACTIVE in the iOS
Supabase project; an unauthenticated Monad address request returned 401. The App
requires a new Xcode run or release build to show Monad in the network selector.

2026-09-23: The native network selector now orders Arbitrum, Monad, Base,
Ethereum, BNB Chain and shows a logo for each. Relay public quotes returned
HyperCore perps destinations for Ethereum native USDC and BNB Binance-Peg USDC.
BNB's token has 18 decimals, unlike the other four 6-decimal tokens; the route
parser validates that precision and the exact contract. Robinhood Chain is
excluded because Relay currently lists no USDC source token for it. These are
quote checks only, not completed transfers. The updated `bsmart-funding`
function is deployed as version 5 and ACTIVE in the iOS Supabase project.
Install a new app build before testing these two new routes. A local anonymous
HTTPS probe was reset by the network, so live address issuance was not verified.

Release compilation and resource/privacy checks passed for the unsigned archive
`build/bSmart-1.0-8-20260922-unsigned.xcarchive`. Signed archiving was rejected by
the local Xcode account/provisioning configuration (Apple sign-in and push
capabilities). This archive has not been signed, exported or uploaded to
TestFlight. Refresh the enrolled developer team's Xcode signing configuration
before generating and distributing the signed archive.

1. In the Relay dashboard, create an application API key. Keep it server-side.
   The live `/requests/v3` endpoint rejected a request without `x-api-key`, despite
   the public quote endpoint working without one. Do not embed a key into iOS.
2. Add the key as Supabase Edge secret `BSMART_RELAY_API_KEY` for the existing iOS
   account project. Keep `BSMART_RELAY_FUNDING_ENABLED=false` until ready.
3. Deploy only `bsmart-funding` from `supabase/ios-account`. The handler validates
   Google/Apple JWTs itself. No database migration or new signing credentials.
4. Set `BSMART_RELAY_FUNDING_ENABLED=true` with the existing global
   `BSMART_DEPOSITS_ENABLED=true` when enabling this version for acceptance.
   The endpoint stays unavailable while either flag/key is missing.
5. Install the new iOS build. Use a user-controlled small test deposit on each
   offered route (native USDC on Arbitrum, Monad, Base, Ethereum; Binance-Peg
   USDC on BNB Chain); compare provider success, actual
   received amount and the same owner's HyperCore balance. Verify repeat use of
   the issued address, app restart, refund/failure states, and account switching.
   No automated test sends funds. No mainnet completion has been claimed.

The app currently offers crypto deposits only. Fiat/card providers require their
own commercial/regional setup and must be checked for deposit-address delivery
and refund compatibility before adding their entry points. Do not call this
integration universal fiat funding.

## User experience and existing funds

New deposit: choose origin network -> receive reusable address and QR -> send
from exchange/wallet -> Relay delivers perps USDC to the existing owner account.
The app calls `/address` without an amount. An internal 20 USDC seed quote registers
the open address; it is not a minimum and is not displayed. An open address is
requoted at actual receipt. The legacy `/quote` endpoint remains compatible. Display
network/asset and the source-chain wallet refund behavior before a user copies it.
External exchange/wallet sending fees are separate from quoted routing costs.
The app refreshes provider history only while the screen is active, every 15s;
Relay continues processing when the app is closed. Existing HyperCore balance
validation, account mode and market collateral checks still gate orders.

Addresses previously copied from the owner's wallet are not managed deposit
addresses. Existing wallet USDC and in-flight CCTP transactions keep their original
manual transfer/history entry. Never silently change or restart those transfers.
Relay refunds to the owner wallet on the source chain, not an exchange hot wallet.

## Small-deposit cost investigation (2026-09-22)

Public provider quotes reproduced 3 USDC -> 1.785620 for an unactivated address
(`userRole: missing`), with 1.214380 USDC under `fees.relayerGas`, zero
`relayerService`, zero `app`, and zero swap impact. A 20 USDC quote for the same
address returned 18.785668, showing mostly fixed rather than proportional cost.
An existing account (`userRole: user`) quoted 3 -> 2.985485 on the same network.
These are diagnostic quotes, not the user's historical quote or completed deposits.
Hyperliquid documents a one-time 1-quote-token activation gas fee. Relay does not
itemize the entire extra execution amount here; do not claim all ~1.214 USDC is
the activation fee or promise a fixed future fee. The observed remaining costs
were not further decomposed. Source-wallet/exchange sending costs are additional.
Removing the amount field does not remove these costs. Sponsorship is not enabled.

Pause new intake with the Relay funding flag. Pausing bSmart's UI does not cancel
provider orders or invalidate already-issued open addresses. Reconcile with Relay
and continue exposing provider history; do not rerun transfers from bSmart.

## Sources

- https://docs.relay.link/features/deposit-addresses
- https://docs.relay.link/references/api/api_guides/hyperliquid-support
- https://docs.relay.link/references/api/get-requests
- https://docs.relay.link/references/api/api-keys
- https://docs.privy.io/wallets/funding/crypto-deposits/overview
- https://docs.privy.io/wallets/actions/swap/overview
- https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/usdc
- https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/activation-gas-fee
