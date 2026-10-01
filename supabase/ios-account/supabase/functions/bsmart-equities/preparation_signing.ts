import { MarketError } from "../bsmart-markets/routing.ts";
import { prepareCowOrder, type PreparedCowOrder } from "./cow_order.ts";
import { assertPreparationMarket, assertStoredPreparation, type PreparationPorts } from "./preparations.ts";

export type EquitySigningPayload = {
  schema: "equity_signing_v1"; state: "signing"; signingStartedAt: string;
  preparationHash: string; prepared: PreparedCowOrder; executionEnabled: false;
};

// Internal codec boundary only. This is not wired to HTTP or a real wallet.
// Persist potential signature exposure BEFORE returning any signable material.
export async function beginPreparedSigning(account: string, id: string, version: number, ports: PreparationPorts): Promise<EquitySigningPayload> {
  const now = ports.now ?? Date.now, p = await ports.ledger.get(account, id);
  if (!p) throw new MarketError("preparation_conflict", 409);
  await assertStoredPreparation(p, account, id);
  if (p.prepared.side !== "buy") throw new MarketError("return_authorization_unavailable", 409);
  if (!["reserved", "signing"].includes(p.state) || p.intent_version !== version) throw new MarketError("preparation_conflict", 409);
  const row = await ports.getIntent(account, id);
  if (row.account_id !== account || row.id !== id) throw new MarketError("intent_not_found", 404);
  await ports.assertIdle(account, p.wallet_address, id);
  await assertPreparationMarket(p.prepared, row, ports.catalogs, now);
  // Same validation as signature acceptance, including current funds, allowance,
  // rebase and the original quote's freshness. No quote refresh/re-sign fallback.
  const checked = await prepareCowOrder(p.material, row, version,
    await ports.preview.state(p.prepared.instrument, p.wallet_address), now(), await ports.boundOwner());
  if (checked.orderUid !== p.order_uid || checked.fingerprint !== p.fingerprint) throw new MarketError("preparation_conflict", 409);
  await assertPreparationMarket(p.prepared, row, ports.catalogs, now);
  if ((await ports.boundOwner()).toLowerCase() !== p.wallet_address) throw new MarketError("wallet_changed", 409);
  const stored = await ports.ledger.startSigning(p);
  await assertStoredPreparation(stored, account, id);
  if (stored.preparation_hash !== p.preparation_hash || stored.state !== "signing" || !stored.signing_started_at || !Number.isFinite(Date.parse(stored.signing_started_at)) ||
    Date.parse(stored.signing_started_at) > now() || Date.parse(stored.expires_at) <= now() + 5000) {
    throw new MarketError("preparation_conflict", 409);
  }
  return { schema: "equity_signing_v1", state: "signing", signingStartedAt: stored.signing_started_at,
    preparationHash: stored.preparation_hash, prepared: structuredClone(stored.prepared), executionEnabled: false };
}
