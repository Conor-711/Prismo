import { GPV2SettlementAbi } from "npm:@cowprotocol/sdk-common@0.14.2";
import { encodeAbiParameters, encodeEventTopics, erc20Abi, type Abi, type AbiParameter, type Hex } from "npm:viem@2.56.3";
import { privateKeyToAccount } from "npm:viem@2.56.3/accounts";
import { NETWORKS } from "../../supabase/functions/bsmart-equities/assets.ts";
import { quoteRequest, validateQuoteArtifacts, type ChainState, type PreviewInput } from "../../supabase/functions/bsmart-equities/quote.ts";
import { prepareCowOrder, type PreparedCowOrder } from "../../supabase/functions/bsmart-equities/cow_order.ts";
import type { IntentRow } from "../../supabase/functions/bsmart-equities/intents.ts";
import type { EVMInstrument } from "../../supabase/functions/bsmart-equities/routing.ts";
import type { CowReconciliationPorts, ReceiptLog, SettlementReceipt } from "../../supabase/functions/bsmart-equities/cow_reconciliation.ts";

// Public deterministic test vector, never a user wallet or production signer.
export const signer = privateKeyToAccount("0x" + "0".repeat(63) + "1" as Hex);
export const owner = signer.address.toLowerCase(), account = "12345678-1234-1234-1234-123456789abc";
export const at = Date.parse("2026-10-01T00:00:00Z");
export const hash = "0x" + "aa".repeat(32), blockHash = "0x" + "bb".repeat(32);
export async function context(side: "buy" | "sell" = "buy", network: "Ethereum" | "Ink" = "Ethereum") {
  const instrument: EVMInstrument = { assetId: account, symbol: "ASTSx", network, chainId: NETWORKS[network].chainId,
    token: "0x1111111111111111111111111111111111111111", usdc: NETWORKS[network].usdc, tokenVariant: "raw", maxLeverage: 1 };
  const input: PreviewInput = { ticker: "ASTS", side, amount: side === "buy" ? "100" : "1", slippageBps: 50, maxNetworkFeeBps: 100 };
  const state: ChainState = { at, chainId: instrument.chainId, owner, token: instrument.token, usdc: instrument.usdc,
    block: "24000000", blockTimestamp: at / 1000 - 12, tokenDecimals: 18, usdcDecimals: 6,
    tokenBalance: "3000000000000000000", usdcBalance: "100000000", tokenAllowance: "3000000000000000000", usdcAllowance: "100000000",
    multiplier: "1100000000000000000", multiplierNonce: "1", activationTime: 0 };
  const request = quoteRequest(instrument, owner, input, state, at);
  const { sellToken, buyToken, receiver, validTo, appData, kind, sellTokenBalance, buyTokenBalance, signingScheme } = request;
  const response = { from: owner, expiration: new Date(at + 60_000).toISOString(), id: 123, verified: true,
    quote: { sellToken, buyToken, receiver, validTo, appData, kind, sellTokenBalance, buyTokenBalance, signingScheme,
      sellAmount: (BigInt(request.sellAmountBeforeFee) * 995n / 1000n).toString(),
      feeAmount: (BigInt(request.sellAmountBeforeFee) / 200n).toString(),
      buyAmount: side === "buy" ? "2000000000000000000" : "100000000", partiallyFillable: false } };
  const { preview, material } = await validateQuoteArtifacts(response, request, instrument, input, state, account, at);
  const row: IntentRow = { id: account, client_intent_id: account, account_id: account, wallet_address: owner,
    request_hash: "ab".repeat(32), input, state: "quoted", version: 1,
    preview: { ticker: "ASTS", side, candidates: [preview], failures: [], executionEnabled: false, gasCoverage: "unverified",
      defaultSaleProceedsDestination: "hyperliquid_perps", returnTransferImplemented: false },
    quote_expires_at: preview.expiresAt, created_at: new Date(at).toISOString(), updated_at: new Date(at).toISOString() };
  const prepared = await prepareCowOrder(material, row, 1, state, at, owner);
  return { instrument, input, state, response, request, material, preview, row, prepared };
}
export function providerOrder(p: PreparedCowOrder) {
  return { ...p.order, owner, uid: p.orderUid, settlementContract: p.domain.verifyingContract, signingScheme: "eip712",
    executedSellAmount: p.order.sellAmount, executedSellAmountBeforeFees: p.order.sellAmount,
    executedBuyAmount: p.order.buyAmount, executedFeeAmount: "0", invalidated: false, status: "fulfilled",
    interactions: { pre: [], post: [] } };
}
export function providerTrades(p: PreparedCowOrder) {
  return [{ orderUid: p.orderUid, owner, sellToken: p.order.sellToken, buyToken: p.order.buyToken,
    sellAmount: p.order.sellAmount, sellAmountBeforeFees: p.order.sellAmount, buyAmount: p.order.buyAmount,
    blockNumber: 24000000, logIndex: 2, txHash: hash }];
}
export function receiptLog(emitter: string, topics: readonly (Hex | Hex[] | null)[], data: Hex, index: number): ReceiptLog {
  if (topics.some(t => typeof t !== "string")) throw Error("incomplete_test_event");
  return { address: emitter.toLowerCase(), topics: topics as [Hex, ...Hex[]], data, logIndex: index,
    transactionHash: hash, blockHash, blockNumber: "24000000", removed: false };
}
export function transfer(token: string, from: string, to: string, amount: string, index: number) {
  return receiptLog(token, encodeEventTopics({ abi: erc20Abi, eventName: "Transfer", args: { from: from as Hex, to: to as Hex } }),
    encodeAbiParameters([{ type: "uint256" }], [BigInt(amount)]), index);
}
export function providerReceipt(p: PreparedCowOrder): SettlementReceipt {
  const settlement = p.domain.verifyingContract!;
  const tradeABI = GPV2SettlementAbi.find(e => e.type === "event" && e.name === "Trade")!;
  const data = encodeAbiParameters(tradeABI.inputs.filter(i => !("indexed" in i && i.indexed)) as AbiParameter[],
    [p.order.sellToken, p.order.buyToken, BigInt(p.order.sellAmount), BigInt(p.order.buyAmount), 0n, p.orderUid]);
  const trade = receiptLog(settlement, encodeEventTopics({ abi: GPV2SettlementAbi as Abi, eventName: "Trade", args: { owner } }), data, 2);
  return { chainId: p.instrument.chainId, finalizedBlock: "24000010", canonicalBlockHash: blockHash,
    transactionHash: hash, blockNumber: "24000000", blockHash, status: "success", logs: [
      transfer(p.order.sellToken, owner, settlement, p.order.sellAmount, 0),
      transfer(p.order.buyToken, settlement, owner, p.order.buyAmount, 1), trade,
    ] };
}
export function evidence(p: PreparedCowOrder): CowReconciliationPorts {
  return { order: async () => providerOrder(p), trades: async () => providerTrades(p), receipt: async () => providerReceipt(p) };
}
