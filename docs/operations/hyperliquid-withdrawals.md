# Legacy Hyperliquid withdrawal archive

This direct withdrawal path is retired. Do not set
`BSMART_WITHDRAWALS_ENABLED=true` or redeploy the old handler. The current
`bsmart-withdrawals` function rejects legacy submission requests with `426`,
and `bsmart-wallet` always reports `withdrawalsEnabled=false` to old clients.

Keep historical `bsmart_withdrawals` rows and related schema until every
in-flight transfer has been independently resolved. Across quote reservation
checks these rows to avoid a second withdrawal against the same wallet.

The only supported withdrawal runbook is [Across withdrawals](across-withdrawals.md).
