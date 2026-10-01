import { createPublicClient, fallback, http } from "npm:viem@2.56.3";
import { ink, mainnet } from "npm:viem@2.56.3/chains";
import { MarketError } from "../bsmart-markets/routing.ts";
import { assertPreparedCowOrder } from "./cow_order.ts";
import { txHash, type CowReconciliationPorts } from "./cow_reconciliation.ts";

export function cowReceiptReader(rpcs: Partial<Record<"Ethereum" | "Ink", string>> = {}, fetcher: typeof fetch = fetch): CowReconciliationPorts["receipt"] {
  const makeClient = (network: "Ethereum" | "Ink") => {
    const chain = network === "Ink" ? ink : mainnet;
    const endpoints = rpcs[network] ? [rpcs[network]!] : network === "Ink"
      ? [...chain.rpcUrls.default.http].reverse() : [...chain.rpcUrls.default.http];
    if (endpoints.some(url => new URL(url).protocol !== "https:")) throw Error("invalid_rpc");
    return createPublicClient({ transport: fallback(endpoints.map(url => http(url, { timeout: 8000, retryCount: 0,
      fetchFn: fetcher, fetchOptions: { redirect: "error" } })), { retryCount: 0 }) });
  };
  const clients = new Map<string, ReturnType<typeof makeClient>>();
  return async (p, hash) => {
    await assertPreparedCowOrder(p);
    const transactionHash = txHash(hash) as `0x${string}`;
    try {
      let client = clients.get(p.instrument.network);
      if (!client) { client = makeClient(p.instrument.network); clients.set(p.instrument.network, client); }
      const chainId = await client.getChainId();
      if (chainId !== p.instrument.chainId) throw Error("rpc_chain_mismatch");
      const receipt = await client.getTransactionReceipt({ hash: transactionHash });
      if (receipt.blockNumber === null || receipt.blockHash === null) return null;
      const finalized = await client.getBlock({ blockTag: "finalized" });
      if (finalized.number === null) throw Error("finality_unavailable");
      const canonical = await client.getBlock({ blockNumber: receipt.blockNumber });
      if (canonical.hash === null) throw Error("canonical_block_unavailable");
      return { chainId, transactionHash: receipt.transactionHash, blockNumber: receipt.blockNumber.toString(),
        blockHash: receipt.blockHash, canonicalBlockHash: canonical.hash, finalizedBlock: finalized.number.toString(),
        status: receipt.status, logs: receipt.logs.map(l => ({ address: l.address, data: l.data,
          topics: l.topics as [`0x${string}`, ...`0x${string}`[]], logIndex: l.logIndex!, transactionHash: l.transactionHash!,
          blockNumber: l.blockNumber?.toString() ?? "", blockHash: l.blockHash!, removed: l.removed })) };
    } catch { throw new MarketError("cow_receipt_unavailable"); }
  };
}
