# Native embedded wallets

## Scope

Privy Swift 2.16.2 supplies user-owned EVM wallets behind existing Supabase
custom JWT identity. Google remains the enabled login provider. Apple must be
linked to the same verified Supabase UUID before it can recover the same wallet;
email matching is not an identity proof. No app secret, refresh token, seed or
private key is sent to the wallet registry.

The existing immutable Supabase address registry and EIP-191 challenge are
unchanged. Privy is authoritative for its user-wallet association; bSmart uses
the Supabase UUID in the verified custom-auth linked account and the exact
registered address. No new DDL or wallet rebinding is part of this rollout.

## Lifecycle

- New accounts resolve their Privy wallet before requesting creation. Creation
  disallows additional Ethereum wallets. Failed/ambiguous creation is retried
  by reading the provider, not by falling back to local key generation.
- Existing matching device keys remain device wallets. Registered addresses
  without a local key are looked up in Privy without creating another wallet.
- Missing configuration, provider errors and mismatching addresses do not mean
  an empty registry and never permit replacement of a funded wallet.
- Supabase remains the only login authority. Only its current access JWT is
  supplied through the SDK token provider; renewal stays in AccountAccessStore.
- Logout/account switching invalidates provider access as well as local leases.
  Backgrounding locks transaction access, but does not log the user out.
- Authenticated wallet inventory is reused without an unconditional user refresh.
  Refresh is required when the registered address is missing or an earlier
  creation has an uncertain result; a failed refresh cannot authorize creation.
- HTTP 429 is surfaced separately, with an in-process 60/120/240/300-second
  cooldown. Repeated taps during cooldown do not call the provider or extend it.
  Success resets the backoff; no create or signing action is automatically replayed.
- Trade entry reconnects an already registered wallet automatically while active,
  without routing through a manual unlock screen. Unregistered accounts retain
  explicit wallet setup; automatic reconnection never creates or binds a wallet.

## Signing

All entry points use one composed wallet vault. Existing durable permits,
owner recovery, expiry checks, nonce allocation, reduce-only semantics and
the common trade sheet are retained. Privy signs but never broadcasts here.
EIP-712 uses the existing JSON codecs; CCTP source transactions use raw
secp256k1 signing of the already-validated 32-byte transaction digest. Do not
replace that operation with personal_sign, which adds a different prefix/hash.

Embedded wallets do not have a locally verified mnemonic. Their provider is an
explicit field in DeviceWalletSummary; backup eligibility must not be represented
by falsely setting recoveryVerified. Local recovery/Face ID controls apply only
to legacy device wallets. Provider recovery does not repair an already-lost
legacy private key.

## Deployment boundary

App ID, iOS App Client ID and Custom Auth/JWKS activation are operator actions.
The iOS implementation alone is not evidence of production login, cross-device
recovery or funded trading. See ../operations/privy-ios-setup.md for activation
and acceptance checks. No automatic legacy private-key upload or fund migration.
