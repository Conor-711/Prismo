# Trading Account

Status: pre-production. Separate from anonymous research installations and local
paper trading. No private key, mnemonic, arbitrary signing payload or simulated
balance may cross this API. Google/Apple identify a person; they do not constitute
proof of control of an Ethereum wallet.

## Current iOS Authentication (2026-09-12)

iOS uses Supabase Auth directly, independently of the research API and its
installation session. See `supabase_account.md` for the current native Google /
Apple exchange, Keychain session namespace and wallet binding Edge Function.
Supabase `auth.users.id` is the account ID. Provider credentials, wallet secrets
and service-role keys must not enter the public-address registry.

Internal build 1.0(6) makes mnemonic backup optional through
`BSMART_INTERNAL_OPTIONAL_WALLET_BACKUP=YES`. This overrides older backup-gate
requirements below only for the explicit internal build. Keys remain device-only;
Google cannot recover a lost key, and existing wallet addresses cannot be replaced.
See `native_perpetual_mvp.md` for the policy and public-release boundary.

The endpoints below are legacy compatibility contracts, not dependencies of the
current iOS login. The earlier backend-mediated Supabase Google adapter is
superseded for iOS. Do not require Vultr to sign in or bind a device wallet.

## Legacy Authentication

`GET /v1/auth/configuration` is public, no-store, and reports enabled providers.
`POST /v1/auth/challenges` requires the existing installation bearer and a provider
(`apple` or `google`). It returns a UUID, random nonce and five-minute expiry.
`POST /v1/auth/sessions` takes the challenge ID, provider and provider ID token.
The backend verifies pinned provider JWKS, RS256, issuer, audience, expiry, issued
time, subject and challenge nonce. A challenge is installation-bound and consumed
atomically once. Identity is keyed by provider + subject, NEVER email or name.

With Supabase Google configured, the challenge additionally returns `providerNonce`
(SHA-256 hex of `nonce`). The native SDK receives `providerNonce`; `/sessions`
requires the original `nonce` (32-128 URL-safe ASCII characters). Both the original
nonce's hash and the Google ID-token nonce must match the stored challenge hash.
Google signature, issuer, audience and authorized party remain verified, followed
by Supabase ID-token admission. Its returned Google identity must match that same
subject. Failure never falls back to a locally admitted session. Supabase session
tokens are not returned or persisted; bSmart account/session/wallet contracts are
unchanged. Supabase identity lifecycle propagation is still a release gate; new
account deletion requests return 503 in this mode. Apple remains disabled here.

The response is an opaque 30-minute account bearer, expiry and account ID/provider.
It does not authorize trading or wallet creation by the server. Account bearer
does not replace installation bearer; `/v1/auth/account` and logout use it only.
Apple additionally requires `authorizationCode` (32-2048 printable ASCII characters);
Google forbids that field. The code is never persisted or returned. After verifying
the native identity token, atomically consume the installation-bound challenge
before one request to Apple's fixed token endpoint. A timeout, rejection or lost
response requires fresh interactive authorization; no automatic code retry.
The returned Apple ID token must independently verify to the same subject, audience
and nonce. Issue an account session only in the transaction that stores the encrypted
Apple refresh credential and consumes the internal short-lived exchange claim.
This claim and the grant never authorize wallet signing or change an existing binding.

Apple refresh credentials are backend-only AES-256-GCM ciphertext, authenticated
against account ID, provider subject and client ID. Encryption keys are loaded from
an operator-provided protected keyring, separate from the Apple ES256 signing key.
No Apple access/refresh token or signing key is sent to iOS. Operators must retain
old encryption key IDs until credentials are re-encrypted; swapping accounts,
clients, key IDs or ciphertext fails decryption. This is provider credential custody,
not wallet custody. App-session renewal is specified separately in
`account_session_refresh.md`; it must not be confused with provider revalidation.
Signed provider revocation receivers and native rejected-session handling are
specified in `account_security_events.md`. Production stream registration and
verification, native account deletion and credential rotation still gate production
enablement. `account_deletion.md` defines the implemented backend deletion/Apple
revocation operation and typed native transport, distinct from logout. Native
confirmation, recovery, persistent-ticket coordination and Google SDK disconnect
are integrated in pre-production. Real-provider verification and expired/lost-ticket
resolution remain release gates; a receipt alone does not complete deletion.

No schema is applied at application startup. An operator must review and apply
the migration. Production authentication remains disabled in this iteration,
even if client IDs are present; development enablement needs an explicit flag.

## Wallet and funds invariants

### Device wallet binding v1

`GET /v1/auth/wallet` (account bearer) returns `{accountId, address}`; null address
is an authoritative unbound state, never inferred from a network error.
`POST /v1/auth/wallet/challenges` takes a lowercase 20-byte `0x` address and returns
`id, accountId, address, nonce, issuedAt, expiresAt`. The nonce is 32 random bytes
encoded as lowercase hex. UTC timestamps are whole seconds. A challenge lasts
five minutes and is bound to the current account session, not just its account.
`PUT /v1/auth/wallet` accepts only `challengeId, signature` (65-byte EIP-191,
low-s, v=27/28). The signed UTF-8 message is exactly:

```text
bSmart wallet binding v1
Audience: https://api.bsmart.today/v1/auth/wallet
Account: <lowercase UUID>
Address: <lowercase 0x address>
Chain ID: 42161
Challenge: <lowercase UUID>
Nonce: <64 lowercase hex digits>
Issued At: <YYYY-MM-DDTHH:MM:SSZ>
Expires At: <YYYY-MM-DDTHH:MM:SSZ>
This only links your wallet to bSmart. It does not authorize a transfer or trade.
```

The client reconstructs this message; it never signs arbitrary server-provided
text. The server reconstructs it from stored challenge fields, verifies control,
then atomically consumes the challenge and creates a unique account/address
mapping. Existing mappings are immutable; a conflicting account or address is
409. Replay/expired/different-session proofs are 401. An uncertain response is
resolved with GET before any retry; the local key is never replaced on timeout.

Local wallet material is independent 256-bit OS entropy, standard BIP39 English
24 words, no extra passphrase, Ethereum path `m/44'/60'/0'/0/0`. Only the mnemonic
entropy is persisted in device-only, passcode-required, user-presence-protected
Keychain. A missing local key for a registered address requires recovery of that
same address. Backup completion is a local re-entry check, not server proof of a
safe offline backup. No receive address/QR or funding enablement follows solely
from binding. There is no wallet replacement or key deletion endpoint.
When another device won initial binding, restoration stores the registered key
in an additional address-specific Keychain slot; it does not overwrite the
unbound key. Registered-address lookup prefers that slot over the pending slot.

- One owner EOA per internal account; local device keys must be matched to the
  server-registered address using a single-use, audience-bound signed challenge.
- No automatic replacement wallet when the local key is missing; show recovery.
- No key material derived from email, subject, OAuth token or password.
- Native Arbitrum One USDC only; 6 decimal integer units. No floating-point money.
- Arbitrum wallet balance, bridge transfer and HyperCore withdrawable balance are
  independent facts. Only confirmed HyperCore balance may fund real orders.
- Only a verified local wallet with verified recovery can expose a receive QR.
  Never render the bridge address as a user's exchange withdrawal destination.
- A successful Arbitrum receipt alone is not proof of HyperCore credit. Track
  transfers by chain/hash/log index plus wallet; handle failures, reorgs and
  uncertain submissions without creating a second payment.
- Mainnet deposit/execution stays off until recovery, signing, reconciliation,
  withdrawal/exit, account lifecycle and independent security review pass.

See `docs/product/arbitrum-usdc-funding.md` for research, UX and release gates.

## Receiving Arbitrum USDC (pre-production)

The native receive page is separate from a CCTP transfer. Its only recipient is the
current local owner, never a token/bridge contract. It requires the existing
`depositsEnabled` gate, an unlocked recovery-verified local wallet, explicit network
confirmation and a fresh account-authenticated registration matching that wallet.
Production configuration still returns false; there is no preview override.

`ArbitrumReceiveStore` keeps a non-persistent address check, bounded by both wall
time and ContinuousClock to 60 seconds including request time. Account/scene/wallet
changes, confirmation withdrawal and refresh invalidate old results. Late responses
cannot restore a cleared address. Each render/copy rechecks current eligibility;
copy is not a signing permission and does not access private material.

`WalletReceiveAddress` uses pinned Wallet Core to encode the full checksum address;
Core Image generates the QR locally from exactly the same public string. The QR is
an address, not a transaction or a promise of chain selection. UI always identifies
Arbitrum One and native USDC, excludes USDC.e, and warns that the sender must choose
that network. Clipboard is device-local with five-minute expiry; it remains usable
when switching to the sending wallet. No amount, private key or account token is
encoded or shared. No balances or deposit-success records are fabricated.

Receiving in the owner wallet does not complete CCTP or credit HyperCore. Separate
transfer/fee confirmation, ETH gas, reconciliation, trading and exit remain required.

## CCTP funding plan v1 (native, not an HTTP signing API)

The legacy Bridge2 is deprecated. New deposit plans use Circle's self-submitted
Arbitrum CctpExtension, NOT its separate sponsored V2 contract. The owner pays
Arbitrum ETH gas. No unlimited token approval or server-selected destination is
accepted. The first route is fixed to mainnet chain 42161, native USDC, source
domain 3, destination domain 19, CctpForwarder as both mintRecipient and
destinationCaller, and the SAME owner in the version-0 HyperCore forwarding hook.
Destination DEX is 0 (default perps); this does not establish HIP-3 spendability.

`Core/Trading/Funding` owns exact-integer quotes, fixed route and immutable plans.
`Core/Wallet` owns ABI/typed-data encoding using pinned Wallet Core. Features may
request public fee estimates but cannot provide contract addresses or payloads.
The fee endpoint is fixed to Circle mainnet `/v2/burn/USDC/fees/3/19` with
`forward=true&hyperCoreDeposit=true`; no account token or private material is sent.
The client reads one unambiguous fast-transfer row, rounds the protocol fee up
to the nearest USDC subunit, adds the high forwarding quote, and shows a 20%
fee ceiling buffer separately. Quotes expire after 60 seconds; errors or stale
quotes are not zero fees and never fall back to legacy Bridge2.

The old 5-USDC bridge minimum is not a CCTP minimum. bSmart's current product
guard requires at least 1 USDC to remain after the maximum CCTP fee as an account
activation reserve, not a guaranteed destination balance. Current public documents
differ on activation timing; CoreDepositWallet also has a configurable deposit fee.
Quote fields are CCTP-only net, not minimum HyperCore credit. Destination fees and
protocol activation require separate pre-signing verification and ledger acceptance.
CCTP's per-message burn
limit is 10 million USDC; this implementation rejects larger amounts instead of
silently batching. Amounts, ceiling and residuals are integer six-decimal units.

A plan requires a matching, recovery-verified device wallet, OS-random nonce and
fresh quote. It fixes total authorization and burn batch amount to the same
value (one message). Authorization expires five minutes after preparation, with
validAfter backdated 30 seconds for inclusion; encoding checks expiry and quote
freshness again. EIP-3009 `ReceiveWithAuthorization` is offchain typed data, NOT a
separate broadcast, and is only usable via an owner-signed extension transaction.
The owner transaction must bind the entire call data; do not relay this V1
authorization as if it bound the hook by itself. The codec does not sign, read
Keychain, broadcast, or enable funds. Quote success is neither balance evidence
nor transfer success. Source preflight, receipt/message/forwarding reconciliation,
durable submission recovery, user confirmation and withdrawal still gate signing.

## Arbitrum source preflight (native, read-only)

`Core/Wallet/CCTPSourceTransaction` is the native source-transaction boundary.
It accepts only a fresh `CCTPSourcePreflight`, never server-supplied raw RLP or a
generic destination/value/chain. Validation reconstructs the signed EIP-3009
calldata and rechecks its exact amount, owner, nonce, gas formula, available funds,
fee ceiling and expiry. `CCTPSourceGasBudget` is shared by simulation and encoding.
The envelope is fixed to EIP-1559 type 2 on chain 42161, extension destination,
zero ETH value/priority tip, and no access list or EIP-7702 authorization.

Wallet Core constructs the signing hash and compiles an externally supplied
65-byte low-s signature after recovering the SAME owner. EIP-3009's v=27/28 is
not accepted as a type-2 yParity=0/1 signature. Raw bytes and their local Keccak
hash are immutable, not taken from RPC. This boundary does not access local keys
or authorize submission. Production signing still requires user confirmation,
durable intent/nonce reservation and submission recovery; encoding alone cannot
unlock receiving, broadcast or trading. Account/background cancellation and fresh
chain checks must run again after user-presence authentication before submission.

Source reads use the fixed Arbitrum One HTTPS RPC, no redirect, cookies, identity
bearer or private key. The queried owner address is public blockchain data, but
is disclosed to the RPC provider. The public endpoint is a development dependency,
not a production SLA or an independent proof of blockchain truth.

Balances and contract configuration must share an EIP-1898 canonical block hash.
Validate chain 42161 before sending the owner; reject stale/future block time,
missing/reorganized blocks, non-EOA owners, absent contract code, wrong USDC
decimals, mismatched extension/messenger/minter/transmitter/domain, paused or
restricted transfers. Record the observed runtime code hashes; code existence
and public getters alone are NOT an independent bytecode/proxy implementation
audit. That audit remains a release gate.

USDC and ETH are exact unsigned 256-bit integers (6 and 18 decimals). Invalid,
missing or oversized RPC quantities never become zero. Source USDC is not a
HyperCore trading balance. A fresh snapshot can display wallet balances without
making a payment or enabling deposits.

Gas preflight consumes only the fixed plan and its verified EIP-3009 signature.
It checks the burn cap, extension allowance, contract minimum fee, unused
authorization, source USDC and ETH, and an uncontended transaction nonce. It
simulates that exact call and estimates Arbitrum gas (including L1 posting cost;
do not add L1 cost again). The preview uses a disclosed 20% gas-limit buffer,
2x observed gas-price ceiling, zero priority fee, and a product safety ceiling
of 0.01 ETH per source transaction; exceeding it requires a new review, not a
silent fee increase. Recheck nonce/canonical block, quote and wallet before
returning. Preflight expires within 30 seconds or the quote expiry, whichever is
earlier. It is not a transaction, nonce reservation, source receipt or destination
credit. Signing/broadcast must later revalidate it and durably journal the exact
transaction before submission; they are not implemented by this read-only layer.

## Device source-transaction journal v1

### Native transfer confirmation (pre-production)

The wallet panel's transfer destination connects the existing CCTP preparation,
protected signer, exact-fee model, journal and broadcaster. It does not call the
exchange API, add simulated balances or claim final credit. Production configuration
remains closed. Preparation now defaults to a denied operation gate; the app provides
a live configuration/current-wallet check that runs at every asynchronous boundary.
There is no UI-only authorization and no test/preview bypass in app configuration.

Amount review fetches a fresh Circle schedule, fixes the owner/amount/route and checks
the source wallet before persisting consent. Separate explicit actions authorize
that one transfer, confirm and sign the bounded ETH fee, and submit the saved signed
transaction. Views receive only a redacted display projection: amounts, owner, fee
ceiling, expiry and public transaction hash, never authorization or raw bytes.
No edited amount or refreshed schedule can mutate an existing consent/transaction.
The confirmation deadline is visible. After submission, the original amount,
recipient and fee ceilings remain visible alongside the persisted status, with no
confirmation action or new deadline; node acknowledgement never implies final credit.

Unsigned cancellation uses the journal, while expiry, uncertain signing/submission
and unresolved history lead to deposit history rather than a fresh payment. A source
failure before any intent is created can be corrected and reviewed again; once an
intent may exist, history/reconciliation is required. Leaving/backgrounding revokes
the preparation scope and cancels the UI task without erasing persisted side effects.
Transient inactive scenes (including system user-presence prompts) hide/disable UI
but do not themselves restart account restoration or revoke foreground permissions.
Background and protected-data-unavailable notifications still revoke signing leases.

### Consent and protected signing extension

The same authenticated event stream also stores fixed-plan consent before any
USDC authorization is created. Consent stages are `review -> authorizing -> authorized`;
only review can be cancelled without chain reconciliation. Its id is carried
unchanged into the source-transaction intent. At most one unlinked consent or
unresolved source transaction may reserve an owner. A source matching a consent
must use its exact plan and authorization; the link is an atomic journal event.
Existing source-only events remain readable, never silently discarded.

An authorizing permit is issued only after persistence and a fresh-plan check.
Already-created authorization signatures are verified and recorded even after
expiry or task cancellation. They do not renew consent or permit submission.
The protected signer exposes only this fixed EIP-3009 authorization and the
validated Arbitrum source envelope. No arbitrary hash, message, address or JSON
signing endpoint is added. A revocable foreground/account lease is checked before
and after protected key access; the actual key record must match the owner/account
and satisfy `DeviceWalletBackupPolicy` (backup optional only in the internal build).
The lease lasts at most 60 seconds and no longer than
the account session. Logout, account reload/sign-in, backgrounding and protected
data lock revoke it; the UI owner must also revoke it on departure. Once a
signature exists, callers must archive it before discarding cancelled UI results.
The protected source signer refuses legacy source-only permits without matching
recorded consent. No production submission is enabled by this work.

`CCTPDepositPreparation` performs fresh account registration and source balance/
route checks before starting consent, repeats those checks before authorization,
then requires a second explicit action after exact-call gas preflight. Protected
authentication must not renew an expired quote, preflight or account scope. It
archives already-created signatures before cancellation checks. An explicit
submission then requires another registration/lease check and a new source-chain
check of the SAME signed transaction. This coordinator is not yet a production
transfer-screen entry point or a credit adapter.

`Core/Trading/Funding/FundingTransactionJournal` owns durable source-transaction
intent/nonce reservations. It is separate from API/installation sessions,
UserDefaults, research cache and server databases. This is not a server migration.
The journal is wired to the purpose-specific protected signer through the native
preparation coordinator and one-shot source broadcaster, not production transfer UI.

A validated `CCTPSourceTransaction` creates a caller-idempotent intent. At most
one unresolved source transaction per owner is admitted, regardless of nonce;
an authorization nonce cannot be reused for another intent. The stages are
`prepared -> signing -> signed -> submitting -> submitted / uncertain`.
Only `prepared` can be cancelled directly. Enter `signing` durably before asking
the owner signer. Persist the exact compiled signature/raw bytes/local hash,
then enter `submitting` durably before returning a one-use submission permit.
Repeating `beginSubmission` does not return another permit or another payment.
The preceding consent event starts before EIP-3009 signing; its UUID is retained
when exact-call preflight creates this source intent.
If a signer finishes after the preflight expires, `recordSignature` still verifies
and durably archives its exact owner signature against the reserved intent. It
does not extend expiry or produce a submission permit. Recording already-created
evidence must not be confused with authorizing a new side effect. This path accepts
only a signature for an existing `signing` intent, not arbitrary raw transactions.
Signature/result callbacks persist already-observed evidence even if their task
was cancelled; cancellation continues to block new signing/submission permits.
Journal errors never reuse preflight wording that claims no transfer occurred.

Node acknowledgement is recorded only for the exact local hash. A mismatch or
missing response is `uncertain`, not a failed/no-payment claim. Neither state
proves a source receipt or HyperCore credit. Signing/submit states survive restart
and expiry and keep the owner/nonce reserved; no timeout/cancellation releases
them. Receipt/reorg/authorization-expiry reconciliation and safe terminal release
are still required before production. No automatic retry or fee replacement.

### One-shot source submission

`ArbitrumSourceSubmissionCheck` repeats source preflight after signing, then
simulates and estimates the exact approved gas/fee envelope at a canonical block.
The nonce, authorization, calldata and observed contract code must still match;
the approved ETH fee cap and USDC amount must still be funded. Changed conditions
cannot increase the user's approved fee or renew the original quote/preflight.
The result is bound to the local transaction hash, lasts at most 10 seconds and
never outlives the original confirmation. It is required before the journal can
issue a submission permit, and is checked again after the durable commit.

The permit is an in-memory single-use reference, not a copyable packet of raw
bytes. It atomically checks the foreground/account lease and starts exactly one
URLSession task. Legacy source-only records lacking consent remain inspectable
but cannot reach this transport. `ArbitrumFundingBroadcaster` accepts only this
permit; its endpoint and `eth_sendRawTransaction` method are fixed. No bearer,
cookies, redirects, retries, alternate destination or caller-provided raw data.
Only the exact local hash in a bounded, correctly correlated JSON-RPC result is
acknowledged. HTTP/RPC errors, malformed replies, disconnects or timeouts are
uncertain. A started request is allowed to finish within its network timeout even
after UI cancellation so its evidence can be archived; cancellation before start
prevents handoff. Recording the result precedes cancelled/account-switched UI
checks. An uncertain or acknowledged record cannot issue another payment permit.
Transport acknowledgement is not a receipt, finality or spendable balance.

Each event is AES-256-GCM sealed with its ledger UUID, sequence and preceding
digest as authenticated data. SQLite stores only sealed events and their digest
chain. Replay verifies transitions, immutable intent/signature, exact canonical
transaction bytes and owner recovery. Historical verification is not a fresh
signing permission and never constructs a newly usable source transaction.
The independent 256-bit journal key and head checkpoint are held in device-only,
passcode-required Keychain (not wallet entropy); files use complete data protection,
0700/0600 permissions and are excluded from backups. No mnemonic/private key is
stored in this database. Raw signed transactions remain sensitive even after
the CCTP authorization expires: the outer Ethereum transaction has no matching
expiry field and could still be included, revert and spend ETH gas until its nonce
is resolved. Never export the bytes to telemetry or release the nonce on a timer.
On physical iOS, protection/permissions/backup exclusion are read back after
configuration and must match. Simulator filesystem tests cannot prove iOS Data
Protection; that physical-device acceptance test is explicitly skipped there.

SQLite uses rollback journaling, `synchronous=EXTRA`, `fullfsync=ON` and bound blob
inserts. A filesystem lock spans each SQLite + Keychain operation across instances.
Before SQLite commit, Keychain stores a pending next checkpoint; afterwards it is
promoted to committed. Recovery accepts only the committed or exact pending head.
A pre-commit interruption retains the old state; a post-commit interruption
finishes that same state. No permit is returned before both stores finish.
Cancellation/expiry after commit withholds the permit but preserves the record.

Missing/corrupt/rolled-back history, unavailable Keychain or a different ledger
key fail closed. Never delete/recreate on error. An unused sequence-zero anchor
may finish initial database creation; an established missing database cannot.
This detects database rollback relative to the surviving Keychain checkpoint,
not an attacker restoring BOTH stores or controlling the unlocked process. App
reinstallation/key loss must reconcile chain state; it must not reset the ledger.
Device restore/lock/power-loss testing and audit remain release gates.

Replay is bounded to 10,000 events / 16 KiB plaintext per event; reaching the bound
pauses writes instead of pruning history. Authenticated archival/retention and
large-history performance acceptance must precede general release. Other owners'
records are not exposed when requesting one account. The public API cannot append
arbitrary decoded records, supply a destination, delete history, or claim credit.

### Source observation and recovery

The fixed read-only RPC also supports transaction/receipt lookup by the exact
local hash. Null is valid only for those two methods, never a zero balance or
successful execution. A lookup first verifies chain 42161, verifies the returned
type-2 transaction against every signed field, and correlates receipt/hash/block/
index/owner/contract. Receipt status is exactly 0 or 1; actual gas and price must
stay within the signed limits. Successful execution requires one MessageSent from
the fixed transmitter and the exact 432-byte source CCTP message: version/domain,
messengers, caller/recipient, USDC, amount, maximum fee and same-owner 56-byte hook.
Offchain-assigned source placeholders must still be zero. This is not an attestation.

Canonical head, receipt block and finalized-tag block are checked independently.
Nonce and authorization state use the same canonical head; final reads recheck
block hashes and transaction/receipt stability. Historical receipt blocks are not
subject to the preflight's 60-second freshness limit. A missing receipt is not
failure; a previously observed receipt disappearing is a reorg only when its old
block hash has changed. Previously finalized source blocks cannot be silently
rewritten even if the finalized height advances. Contradictory/stale replies fail closed. Source data
finality is distinct from rollup state settlement and HyperCore credit.

Observations append to the existing encrypted journal as a separate event, linked
to the immutable source intent and previous observation ID. Old events remain
readable. Late concurrent results cannot overwrite newer evidence. Source
submission state/nonce reservation is never reset by observation, even for a
finalized revert or missing transaction. History offers an explicit read-only
source check after current account registration, never rebroadcast or raw export.
Queries are not automatic on opening history. Cancellation clears UI; already
verified returned evidence is saved before discarding an obsolete completion.
Destination reconciliation, safe terminal release and production enablement remain
separate gates.

### CCTP attestation observation

A manual cross-chain check first refreshes and journals the exact source receipt.
Only a successful, currently canonical source message can be sent to Circle's
fixed `/v2/messages/3?transactionHash=...` endpoint. No provider credentials,
wallet keys, authorization signatures or raw transaction are included. API
`complete` and forward status are not receipt/credit evidence. One source message
means exactly one response message; unexpected multiplicity/version/hash fails
closed. A 404 or documented pending status remains waiting, not a failed deposit.
`eventNonce` is parsed as an exact bytes32 hex value or a bounded decimal uint256
and must equal the signed nonce; never parse it through floating point. Pending
messages require `PENDING` attestation and a null/empty-hex message. The API's
transaction association remains a Circle HTTPS assertion: source transaction hash
is not itself inside the signed CCTP message. This is not a trustless light client.

The attested bytes must match the verified source message except the four fields
Circle fills: nonce, executed finality, executed fee and expiration block. Nonce
must be nonzero, executed finality supported, and actual fee within the original
ceiling. Recover every low-S legacy-v signature from Keccak(message), in strictly
increasing distinct address order. Do not derive a quorum from the API key count.
The destination MessageTransmitter on chain 999 must report exactly the required
number of enabled signatures, version 1 and local domain 19. Its RPC only supports
latest state, so contract reads are bracketed by identical fresh latest blocks;
changed or stale heads cannot certify a snapshot. Contract pause and used nonce
are observed separately, never translated to account credit. No RPC failover or
automatic transaction submission is introduced.
The client supports up to 16 signatures as a resource bound, not a protocol quorum.
The latest verified destination snapshot is retained even across subsequent
pending API responses; later observations cannot regress its block or unconsume
the same nonce. A snapshot/code hash is not an audit of the deployed proxy implementation.

Attestation observations are durable independent events tied to intent, exact
source observation and previous attestation observation. Replay revalidates the
message and signatures against the recorded verifier state. Concurrent source
changes invalidate stale attestation completions; later source changes hide the
prior attestation projection without erasing evidence. Expiration/re-attestation
never authorizes a second source payment. Destination receipts, forwarding and
HyperCore per-deposit credit remain necessary before credit or nonce release.

### Destination forwarding observation

Only an authenticated current source/attestation lookup can trigger a fixed
chain-999 receipt query for Circle's recorded forwarding hash. No arbitrary URL,
caller-supplied replacement transaction, retry broadcast or balance write is exposed.
A successful RPC receipt is insufficient: the exact CCTP nonce, source domain,
sender, executed finality and 284-byte burn body must match MessageReceived from
the fixed transmitter. Within that nonce's synchronous interval, require the
native HyperEVM USDC Transfer from forwarder to CoreDepositWallet, its system
Transfer, optional NewCoreAccountFeeApplied and SendAsset, and the closing
MintAndForward event for the original owner/token/wallet/requested DEX/amount.
The next MessageReceived cannot supply missing events. Relayer top-level calldata
is not assumed to be a single direct call; fixed-emitter logs provide correlation.

All receipt/log hashes, block numbers, transaction indexes, monotonic unique log
indexes, removed flags, topics and ABI lengths are checked. The raw response is
bounded by the existing 256-KiB transport, at most 128 logs and 2-KiB log bodies;
only 4-6 relevant events are archived. Unsupported/malformed receipts fail closed.
Fees use exact uint256 subtraction; forwarding converts six to eight decimals
and validates uint64 limits. A configured account fee must reconcile exactly with
the SendAsset amount. A system Transfer directly naming the owner, without
SendAsset, is a spot fallback even though the hook/footer requested perps DEX 0.

Canonical receipt/block are read again, and the latest nonce read must be bracketed
by an identical fresh HyperEVM head. The current block cannot regress from the
attestation snapshot. A missing receipt can be recorded as waiting, but failure
status or unrelated events do not identify this deposit and are errors. An accepted
HyperBFT receipt cannot later disappear or be replaced; inconsistency requires
review, not a new source payment. This is RPC evidence, not a cryptographic light
client or proof of the deployed proxy implementation.

Forwarding observations link intent, source observation, attestation and previous
forward observation. Journal replay revalidates them, commit recovery is atomic,
and late/foreign/competing results cannot supersede current evidence. New source or
attestation observations hide stale UI while retaining accepted receipt history.
The history action performs registration -> source -> attestation -> forwarding;
verified results are archived before checking page departure/logout/cancellation.
Neither processed nonce, forwarder success nor SendAsset is a HyperCore ledger
receipt. Actual credit, tradable balances, safe terminal release, fee consent,
withdrawal and real trading remain required. Production capabilities stay disabled.

### Read-only HyperCore balances

The verified device-wallet panel may explicitly request public balances from the
fixed mainnet Hyperliquid `/info` endpoint. Recheck the current account's registered
owner before disclosure. Only userAbstraction, spotClearinghouseState and default
DEX clearinghouseState requests are allowed; never exchange actions, signatures,
product sessions, cookies, custom endpoints or automatic network refreshes.

Read the abstraction mode before and after the balance queries and reject changes.
Unified account and portfolio margin use spot USDC as the token balance source;
do not interpret their often-zero default-perps summary as absence of funds. For
default/disabled/DEX-abstraction modes, display spot USDC separately from default
perps equity and withdrawable amount. Never sum these fields, treat equity as cash,
infer HIP-3 buying power, or derive an available balance by subtracting hold.
Only token index 0 with exact USDC identity is accepted as USDC. Malformed, unknown
mode, duplicate or contradictory data is an error, not zero; a valid empty spot
balance list is zero at the queried address. Decimal strings are parsed exactly to
8-decimal integer units, with signed equity distinct from unsigned token balances.

The multi-request result is a short-lived API observation, not an atomic chain
snapshot, deposit receipt or execution authorization. Default-perps server time
must be recent; spot data has no server timestamp, so show local check time rather
than an invented block time. Expire the entire display after at most 30 seconds.
Logout, background, locked wallet, cancellation and changed registration invalidate
pending UI results; errors clear old data. No balance is persisted, added to the
paper account, or used to release a funding intent. Exact per-deposit HyperCore
system-action correlation, real execution checks and production gates remain required.

### History presentation

`FundingHistoryEntry` projects one verified journal snapshot to a minimal UI
record: ID, account/owner, original amount and fee ceilings, dates, stage,
optional local transaction hash and observed source fee/data finality. It excludes authorization signatures, calldata,
signing hashes and raw signed transaction bytes. Consent and its linked source
appear once, with the source stage taking precedence. Legacy source records remain
visible. Node acknowledgement is named as such, never as successful execution or
HyperCore credit. Expiry alone does not change a recorded stage.

`FundingHistoryStore` requires a current matching account/wallet registration
before reading local history or cancelling a review. It rejects foreign/duplicate
records and stale completions, and clears displayed data on errors or invalidation.
The SwiftUI entry is in the verified wallet panel, with no send/retry/receive action.
An empty list means no verified records on THIS device, not proof of zero on-chain
activity. A corrupt, missing or locked ledger is an error, never an empty list.
Historical public wallet/hash identifiers use unmodified, horizontally scrollable
text and explicit copy actions. Do not insert visual hyphens, copy authorization
material, or turn this inspection control into a new receiving-address flow.

An explicit, confirmed `cancelReview` rereads both lifecycles under the same ledger
lock. Only consent `review` or source `prepared` can become cancelled, including
after restart/quote expiry. Cancellation is idempotent; it does not delete the
authorization or cancel a network transaction. A stale screen cannot cancel an
issued signing/authorization permit. Authorizing, authorized-but-unlinked, signing,
signed and submission states require future chain reconciliation; no timer,
history refresh or cancellation dialog releases them. The history page clears
on background, page departure or wallet/account changes. Source observations do not
open real funding or establish destination credit; live receipt/reorg behavior
and independent RPC/proxy verification still require acceptance.
