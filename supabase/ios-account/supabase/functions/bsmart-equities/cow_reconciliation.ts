import { GPV2SettlementAbi } from "npm:@cowprotocol/sdk-common@0.14.2";
import { decodeEventLog, erc20Abi, type Abi, type Hex } from "npm:viem@2.56.3";
import { MarketError, object } from "../bsmart-markets/routing.ts";
import { address, raw } from "./quote.ts";
import { assertPreparedCowOrder, type PreparedCowOrder } from "./cow_order.ts";

export type ReceiptLog = { address: string; data: Hex; topics: [Hex, ...Hex[]]; logIndex: number;
  transactionHash: string; blockHash: string; blockNumber: string; removed: boolean };
export type SettlementReceipt = { chainId: number; finalizedBlock: string; canonicalBlockHash: string;
  transactionHash: string; blockNumber: string; blockHash: string; status: "success" | "reverted"; logs: ReceiptLog[] };
export type CowReconciliationPorts = {
  order: (p: PreparedCowOrder) => Promise<unknown>;
  trades: (p: PreparedCowOrder) => Promise<unknown>;
  receipt: (p: PreparedCowOrder, hash: string) => Promise<SettlementReceipt | null>;
};
export type CowObservation = { orderUid: string; state: "pending" | "unknown" | "needs_reconciliation" | "confirmed";
  providerStatus: string | null; executedInputAmountRaw: string | null; receivedOutputAmountRaw: string | null;
  saleProceedsUsdcRaw: string | null; transactionHash: string | null; checkedAt: string; error: string | null;
  resubmitAllowed: false; returnReady: false };
const mismatch = () => new MarketError("cow_evidence_mismatch");
export function txHash(value: unknown): string {
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(value)) throw mismatch();
  return value.toLowerCase();
}
function orderEvidence(value: unknown, p: PreparedCowOrder) {
  const r = object(value), o = p.order;
  if (r.uid !== p.orderUid || address(r.owner) !== p.owner || address(r.receiver) !== p.owner ||
    address(r.settlementContract) !== address(p.domain.verifyingContract) ||
    address(r.sellToken) !== o.sellToken || address(r.buyToken) !== o.buyToken ||
    r.sellAmount !== o.sellAmount || r.buyAmount !== o.buyAmount || r.feeAmount !== "0" ||
    r.validTo !== o.validTo || r.appData !== o.appData || r.signingScheme !== "eip712" ||
    r.kind !== "sell" || r.partiallyFillable !== false || r.sellTokenBalance !== "erc20" || r.buyTokenBalance !== "erc20" ||
    !["open", "fulfilled", "cancelled", "expired", "presignaturePending"].includes(r.status as string) ||
    typeof r.invalidated !== "boolean" || r.executedFeeAmount !== "0" ||
    r.executedSellAmountBeforeFees !== r.executedSellAmount) throw mismatch();
  if (r.interactions !== undefined) {
    const interactions = object(r.interactions);
    if (Object.keys(interactions).some(k => !["pre", "post"].includes(k)) ||
      [interactions.pre, interactions.post].some(v => v !== undefined && (!Array.isArray(v) || v.length))) throw mismatch();
  }
  raw(r.executedSellAmount); raw(r.executedBuyAmount);
  return r;
}
function tradeEvidence(value: unknown, p: PreparedCowOrder, r: Record<string, unknown>) {
  if (!Array.isArray(value) || value.length !== 1) throw mismatch();
  const trade = object(value[0]);
  if (trade.orderUid !== p.orderUid || address(trade.owner) !== p.owner ||
    address(trade.sellToken) !== p.order.sellToken || address(trade.buyToken) !== p.order.buyToken ||
    trade.sellAmount !== r.executedSellAmount || trade.sellAmountBeforeFees !== trade.sellAmount ||
    trade.buyAmount !== r.executedBuyAmount || !Number.isSafeInteger(trade.blockNumber) || (trade.blockNumber as number) <= 0 ||
    !Number.isSafeInteger(trade.logIndex) || (trade.logIndex as number) < 0) throw mismatch();
  return { hash: txHash(trade.txHash), block: String(trade.blockNumber), logIndex: trade.logIndex as number };
}

function receiptEvidence(receipt: SettlementReceipt, p: PreparedCowOrder,
  trade: { hash: string; block: string; logIndex: number }, input: string, output: string) {
  if (receipt.chainId !== p.instrument.chainId || receipt.status !== "success" ||
    txHash(receipt.transactionHash) !== trade.hash || raw(receipt.blockNumber, true) !== trade.block ||
    txHash(receipt.blockHash) !== txHash(receipt.canonicalBlockHash) || !Array.isArray(receipt.logs) || receipt.logs.length > 4096) throw mismatch();
  if (BigInt(raw(receipt.finalizedBlock)) < BigInt(receipt.blockNumber)) return false;
  let tradeCount = 0, inputNetOut = 0n, outputNetIn = 0n;
  const indices = new Set<number>();
  for (const log of receipt.logs) {
    if (!Number.isSafeInteger(log.logIndex) || log.logIndex < 0 || indices.has(log.logIndex) || log.removed !== false ||
      txHash(log.transactionHash) !== trade.hash || txHash(log.blockHash) !== txHash(receipt.blockHash) ||
      log.blockNumber !== receipt.blockNumber) throw mismatch();
    indices.add(log.logIndex);
    const emitter = address(log.address);
    if (emitter === address(p.domain.verifyingContract)) {
      let event;
      try { event = decodeEventLog({ abi: GPV2SettlementAbi as Abi, topics: log.topics, data: log.data, strict: true }); }
      catch { throw mismatch(); }
      if (event.eventName !== "Trade") continue;
      const args = object(event.args);
      if (args.orderUid !== p.orderUid) continue;
      if (++tradeCount !== 1 || log.logIndex !== trade.logIndex || address(args.owner) !== p.owner ||
        address(args.sellToken) !== p.order.sellToken || address(args.buyToken) !== p.order.buyToken ||
        String(args.sellAmount) !== input || String(args.buyAmount) !== output || args.feeAmount !== 0n) throw mismatch();
    } else if (emitter === p.order.sellToken || emitter === p.order.buyToken) {
      let event;
      try { event = decodeEventLog({ abi: erc20Abi, topics: log.topics, data: log.data, strict: true }); }
      catch { continue; } // Issuer-specific rebase events are not ERC20 transfers.
      if (event.eventName !== "Transfer") continue;
      const args = event.args as { from: string; to: string; value: bigint };
      const fromOwner = args.from.toLowerCase() === p.owner, toOwner = args.to.toLowerCase() === p.owner;
      const delta = (toOwner ? args.value : 0n) - (fromOwner ? args.value : 0n);
      if (emitter === p.order.buyToken) outputNetIn += delta;
      if (emitter === p.order.sellToken) inputNetOut -= delta;
    }
  }
  // Balance changes from other orders/deposits are not proof for this UID. When a
  // batch is ambiguous, hold it for reconciliation rather than attributing funds.
  if (tradeCount !== 1 || inputNetOut !== BigInt(input) || outputNetIn !== BigInt(output)) throw mismatch();
  return true;
}

// Read only. Neither provider status nor a timeout can authorize a retry, release
// a reservation, claim a leg, or start the sale-return leg.
export async function reconcileCowOrder(p: PreparedCowOrder, ports: CowReconciliationPorts,
  now: () => number = Date.now): Promise<CowObservation> {
  await assertPreparedCowOrder(p); // Expired orders remain recoverable by their original UID.
  const result: CowObservation = { orderUid: p.orderUid, state: "unknown", providerStatus: null,
    executedInputAmountRaw: null, receivedOutputAmountRaw: null, saleProceedsUsdcRaw: null,
    transactionHash: null, checkedAt: new Date(now()).toISOString(), error: null, resubmitAllowed: false, returnReady: false };
  try {
    const order = orderEvidence(await ports.order(p), p);
    result.providerStatus = order.status as string;
    const input = raw(order.executedSellAmount), output = raw(order.executedBuyAmount);
    if (order.status === "open" && input === "0" && output === "0" && order.invalidated === false) {
      result.state = "pending";
    } else if (["expired", "cancelled"].includes(order.status as string) && input === "0" && output === "0") {
      // Off-chain cancellation is not on-chain invalidation or no-fill proof.
      result.error = "cow_terminal_requires_reconciliation";
    } else if (order.status !== "fulfilled" || order.invalidated !== false || input !== p.order.sellAmount ||
      BigInt(output) < BigInt(p.order.buyAmount)) throw mismatch();
    else {
      const trade = tradeEvidence(await ports.trades(p), p, order);
      const receipt = await ports.receipt(p, trade.hash);
      if (!receipt || !receiptEvidence(receipt, p, trade, input, output)) {
        result.state = "pending"; result.error = "cow_receipt_not_finalized";
      } else {
        result.state = "confirmed"; result.transactionHash = trade.hash;
        result.executedInputAmountRaw = input; result.receivedOutputAmountRaw = output;
        result.saleProceedsUsdcRaw = p.side === "sell" ? output : null;
      }
    }
  } catch (error) {
    const code = error instanceof MarketError ? error.code : "cow_reconciliation_unavailable";
    result.state = code === "cow_evidence_mismatch" ? "needs_reconciliation" : "unknown";
    result.error = code;
  }
  result.checkedAt = new Date(now()).toISOString();
  return result;
}
