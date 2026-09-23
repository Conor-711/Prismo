# Native Perpetual MVP

Embedded-wallet update (2026-09-12): new accounts use Privy user-owned EVM
wallets through Supabase custom JWT. Existing local wallets remain unchanged.
Both providers feed the same trade UI, journal, validation and broadcasting.
Only legacy device wallets use local recovery/Face ID controls; Privy recovery
does not depend on a local mnemonic or the internal optional-backup flag.
See `embedded_wallet.md` for the current lifecycle and deployment boundary.
Local-only wallet statements below describe the preserved legacy provider.

2026-09-12 verification: `/tmp/bsmart-wallet-auth-policy-v2.xcresult` passes
40 wallet/setup/signing tests, including atomic policy persistence/failure,
unchanged key/address, context reuse/background invalidation, and automatic
setup/read-back without repeated writes. Architecture/terminology/diff checks
pass. Tests use isolated keychain adapters and public test keys; physical-device
Face ID and funded account acceptance remain to be verified by the user.

- Google/Supabase authenticates the person; the wallet registry binds only a
  public address. Device-only Keychain owns signing keys. No private key export
  to Supabase, research API or an application server.
- The basic route is wallet unlock, Arbitrum native USDC receive, CCTP transfer,
  automatic unified USDC setup, perpetual IOC market order, reduce-only close,
  Arbitrum USDC withdrawal. No spot trading and no builder fee before configuration.
- Internal build 1.0(6) makes backup optional via the explicit build setting
  `BSMART_INTERNAL_OPTIONAL_WALLET_BACKUP=YES` (including its Release archive).
  `DeviceWalletBackupPolicy` is shared by UI, funding, trading and signing gates;
  absent/invalid/NO configuration requires backup. Set NO before public release.
  Skipping backup does not write `recoveryVerified=true`, alter keys/addresses,
  weaken device authentication, or grant cloud capabilities. The optional backup
  entry stays available. Google does not recover a missing local key; an existing
  registered wallet with no matching local key remains blocked, never replaced.
- Unified setup is a fixed `userSetAbstraction(unifiedAccount)` user-signed
  action for the current owner only. It is prepared automatically once per setup
  session under the internal app's default unified-balance policy. It requires a flat
  account with no open orders, a current verified registration and a revocable
  device signing lease. It shares durable nonce allocation with orders and
  withdrawals. A server response alone never marks the mode enabled; read it back.
- Settings can disable wallet user-presence checks. Legacy/new records default to
  enabled; changing it updates the original Keychain ACL and policy together, never
  deletes or replaces a key. Disabled mode remains passcode-set/device-only, but
  an unlocked, signed-in device can authorize operations without further Face ID.
  Continuous operations reuse an account-scoped LAContext for at most 60 seconds;
  background, protected-data lock, sign-out and policy change invalidate it. No
  secret bytes are cached in this session. First disabling an older protected item
  may still require system authentication. A failed update keeps the old setting.
- First-version unified withdrawals require all perpetual positions and orders
  closed and zero USDC hold. Never treat a unified account's per-DEX balance as
  free collateral. Portfolio-margin withdrawals remain unsupported.
- Quotes and sizes are exact decimal quantities. Funding/order/withdrawal
  submission requires confirmation and a fresh preflight. Unknown responses do
  not trigger automatic retries. API acceptance is not destination arrival.
- Deposits, orders and withdrawals have separate authenticated registry gates.
  Local tests and read-only live checks are not proof of funded mainnet execution.

2026-09-12 optional-backup validation: simulator build and 191 targeted tests
passed, including unbacked deposit/device order signing, withdrawal, unified
setup, unchanged recovery flags and session revocation. Three login/wallet-entry
UI tests also passed. No funded transaction or key migration was performed.
The built Info.plist contains the explicit YES flag.

References: [account modes](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/account-abstraction-modes),
[signing SDK](https://github.com/hyperliquid-dex/hyperliquid-python-sdk/blob/master/hyperliquid/utils/signing.py),
[CCTP withdrawals](https://developers.circle.com/cctp/howtos/withdraw-usdc-from-hypercore-to-evm).
