import { readJSON } from "../bsmart-markets/providers.ts";
import { MarketError } from "../bsmart-markets/routing.ts";
import { NETWORKS } from "./assets.ts";
import { assertPreparedCowOrder, type PreparedCowOrder } from "./cow_order.ts";
import { txHash, type CowReconciliationPorts } from "./cow_reconciliation.ts";

export function cowStatusReader(receipt: CowReconciliationPorts["receipt"], fetcher: typeof fetch = fetch): CowReconciliationPorts {
  const read = async (p: PreparedCowOrder, trades: boolean) => {
    await assertPreparedCowOrder(p);
    const base = `https://api.cow.fi/${NETWORKS[p.instrument.network].api}/api/v1/`;
    const path = trades ? "trades?" + new URLSearchParams({ orderUid: p.orderUid, offset: "0", limit: "2" }) : `orders/${p.orderUid}`;
    try { return await readJSON(base + path, { method: "GET" }, fetcher); }
    catch { throw new MarketError("cow_status_unavailable"); }
  };
  return { order: p => read(p, false), trades: p => read(p, true), receipt: async (p, hash) => {
    await assertPreparedCowOrder(p);
    return await receipt(p, txHash(hash));
  } };
}
