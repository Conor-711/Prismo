# CCTP Deposit Simulation Recovery

## Reproduction

On 2026-09-12 the official Arbitrum RPC reproduced the user's failure using a
public disposable test key and temporary `eth_call` state overrides. The simulated
wallet had 2.99418 native USDC and 0.0011 ETH, with a 2.8 USDC deposit. No device
key, real wallet data, transaction signature, or broadcast endpoint was used.

At block `0x1e0d0a39`, base fee was 20,006,000 wei. The old fee-bearing call omitted
`gas`, causing the node to use 50,000,445 gas and demand 2,000,617,805,340,000 wei
(about 0.002 ETH), more than the simulated balance. RPC returned -32000:
`insufficient funds for gas * price + value`. The app had hidden this reason as
the generic simulation error.

The same calldata with an explicit 1,500,000 gas bound returned `0x` (successful
simulation). `eth_estimateGas` returned `0x2cffa` (184,314 gas). Production now
estimates first, applies the existing 20% gas buffer and gas-price ceiling,
checks balance against that budget, then simulates with this explicit gas limit.
The quote is a point-in-time diagnostic, not a promised network fee.

The final probe at block `0x1e0d1257` repeated the old failure, estimated 184,273
gas, and succeeded with the production-equivalent 20% buffer (221,128 gas).
The maximum simulated fee budget was 8,868,117,312,000 wei (0.000008868117312 ETH),
well within 0.0011 ETH. This also used temporary state only.

Local build and regression: `/tmp/bsmart-deposit-gas-recovery.xcresult`, 107 tests
passed with no failures/skips. Coverage includes the bounded call, RPC error
classification, failed attempt -> new deposit, legacy authorization recovery,
journal restart/evidence preservation, and refusing to release signed transfers.
Architecture, terminology, strings plist and diff checks passed.

## Recovery

- A saved USDC authorization is not a signed Arbitrum transaction. The fixed
  CctpExtension calls receiveWithAuthorization with `from = msg.sender`; its
  authorization alone cannot broadcast this user's deposit.
- After preflight failure, a journal-verified orphan in `authorized` state becomes
  `notSubmitted`. Signature, amount, nonce and history remain. A new explicit
  request can immediately use a new authorization nonce, without visiting history.
- The transition is refused if a source record exists or an authorization signer
  is still in flight. The closed attempt cannot later reserve a source transaction.
- Older saved authorizations resume with a fresh estimate; if that fails, the same
  closure applies. Signed/sent/unknown source transactions are never deleted or
  automatically resubmitted. The old chain-expiry recovery remains available.
- History exposes Continue deposit, not a misleading "mark reviewed" control.

This confirms a reproducible integration defect, not the exact RPC response from
the user's phone. Real funded end-to-end acceptance still belongs to the user.

Protocol references: [Circle Arbitrum-to-HyperCore guide](https://developers.circle.com/cctp/howtos/transfer-usdc-from-arbitrum-to-hypercore),
[CctpExtension implementation](https://github.com/circlefin/hyperevm-circle-contracts/blob/master/src/CctpExtension.sol).

## Submission Fee Headroom Follow-up

The subsequent "network fee exceeds the deposit safety limit" report exposed a
second integration defect. Submission compared a fresh estimate * 1.2 to the
already-approved original estimate * 1.2, twice (fresh preflight and final capped
estimate). Thus an estimate changing from 200,000 to 200,001 failed despite the
signed 240,000 gas limit. Both comparisons now use the raw new estimate. Tests
cover 200,001, 220,000 and 240,000 within budget, 240,001 over budget, price-cap
changes, unchanged signed envelopes, and final-only estimate changes.

The absolute 5,000,000 gas / 0.01 ETH ceilings remain unchanged. Actual quote
overruns request a new quote/confirmation, rather than suggesting insufficient
funds or silently modifying a signed transaction.

A follow-up mainnet read-only probe at block `0x1e0d9348` estimated 184,438 gas,
quoted 221,326 gas and a maximum fee of 8,882,255,032,000 wei
(0.000008882255032 ETH). Bounded calls at blocks `0x1e0d9368`, `0x1e0d9372`, and
`0x1e0d937f` succeeded. Estimates were stable in this sample; the one-unit
fluctuation failure is reproduced by deterministic tests, not claimed as a
captured response from the user's phone. The probe used only temporary state
overrides and a public disposable authorization key, with no broadcast call.

Pre-submit failures may leave a source transaction signed but never submitted.
`signed -> notSubmitted` is now an authenticated terminal event retaining all
original evidence. The journal commits `submitting` before issuing the sole
broadcast capability, so that transition cannot coexist with a submission permit.
Recovery refuses in-flight signing, issued permits, ambiguous results and chain
evidence of activity. A not-found lookup alone does not prevent closure. The old
signed intent cannot be revived; a new deposit needs a new authorization and
explicit confirmation. Restoring an older failed attempt uses the same rule.
Terminal history no longer offers source/cross-chain checks that cannot run.

Final verification: iOS build and 117 tests passed, zero failures/skips,
`/tmp/bsmart-deposit-fee-headroom-final.xcresult`. No funded acceptance transaction
was sent. Existing device installs must be updated in place, never uninstalled
to clear this issue.
