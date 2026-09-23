# Across withdrawal rollout

Across is the only supported withdrawal path. The legacy endpoint rejects old
submission requests with `426`, and `bsmart-wallet` always reports
`withdrawalsEnabled=false` to installed old builds. Retain the old database
records only to prevent duplicate withdrawals while historical transfers are
unresolved. The supported switch is `BSMART_ACROSS_WITHDRAWALS_ENABLED`.

As of 2026-09-23, the project owner confirmed both migrations, the worker job,
and the Across secrets. The Across switch is on at the owner's request; the
legacy switch is off. Deployment and anonymous authorization checks passed,
but no funded end-to-end canary or destination receipt has been confirmed.

## Prerequisites

1. In Supabase project `dzyitinagewdfkzjkuiz`, run migrations
   `202609230005_across_withdrawals.sql` and
   `202609230006_across_reconciliation.sql` in order. Confirm the worker job
   `bsmart-across-reconcile` is active. Never copy the Vault worker token to
   an app or a terminal log.
2. Configure `ACROSS_API_KEY` (with `swap-gasless` permission) and
   `ACROSS_INTEGRATOR_ID` (four hexadecimal digits prefixed by `0x`) as
   Supabase Edge Function secrets. Do not put them in iOS or Git.
3. Deploy both `bsmart-wallet` and `bsmart-withdrawals` from
   `supabase/ios-account`, then verify unauthenticated requests return 401.
   Check the scheduled `reconcile` endpoint rejects a missing or wrong
   worker token. The legacy capability must remain hardcoded false.
4. Ship a new iOS build that reads `acrossWithdrawalsEnabled`. Old builds only
   see `withdrawalsEnabled=false` and cannot submit through the old endpoint.

## Canary

The Across flag is global, not account-scoped. Before treating the rollout as
verified, use a small funded test account: quote HyperCore USDC, verify source balance,
recipient, input, minimum arrival, `fees.submission`, and refund destination;
sign both returned steps. Do not re-send the same submission after a timeout.
Track the Across deposit ID to `filled` on Arbitrum and reconcile the actual
USDC receipt. Repeat for the supported spot/perps balance modes before wider
rollout. Across' submit response is not final settlement proof.

Monitor the states `submitting`, `uncertain`, `deposit_pending`, and `expired`.
Investigate any row stuck in `submitting` or `uncertain` manually using the
deposit ID; do not clear its one-wallet reservation or re-submit a signed
quote without evidence it never reached Across. An `expired` deposit can take
hours to refund on HyperEVM. It remains reserved until `refunded` or `filled`.

To stop new withdrawals, set `BSMART_ACROSS_WITHDRAWALS_ENABLED=false`.
The GET/history and scheduled reconciliation paths remain available so
in-flight transfers can reach terminal status. Never re-enable the legacy path.

Official provider flow: https://docs.across.to/introduction/hypercore-withdrawals
