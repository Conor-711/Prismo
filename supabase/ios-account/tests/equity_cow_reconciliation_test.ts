import { strict as assert } from "node:assert";
import { cowStatusReader } from "../supabase/functions/bsmart-equities/cow_status.ts";
import { cowReceiptReader } from "../supabase/functions/bsmart-equities/cow_receipt.ts";
import { reconcileCowOrder } from "../supabase/functions/bsmart-equities/cow_reconciliation.ts";
import { at, blockHash, context, evidence, hash, owner, providerOrder, providerReceipt, providerTrades, transfer } from "./fixtures/equity_cow.ts";

Deno.test("CoW confirmed requires API trade, finalized receipt and actual input/output transfers", async () => {
  for (const side of ["buy", "sell"] as const) {
    const { prepared: p } = await context(side);
    const result = await reconcileCowOrder(p, evidence(p), () => at);
    assert.equal(result.state, "confirmed"); assert.equal(result.executedInputAmountRaw, p.order.sellAmount);
    assert.equal(result.receivedOutputAmountRaw, p.order.buyAmount);
    assert.equal(result.saleProceedsUsdcRaw, side === "sell" ? p.order.buyAmount : null);
    assert.equal(result.returnReady, false); assert.equal(result.resubmitAllowed, false);
  }
});
Deno.test("CoW recovery queries the original UID even after quote expiry", async () => {
  const { prepared: p } = await context();
  const result = await reconcileCowOrder(p, evidence(p), () => at + 3600_000);
  assert.equal(result.orderUid, p.orderUid); assert.equal(result.state, "confirmed");
});
Deno.test("CoW open is pending, not filled; no trade or RPC requests", async () => {
  const { prepared: p } = await context(), ports = evidence(p);
  ports.order = async () => ({ ...providerOrder(p), status: "open", executedSellAmount: "0", executedSellAmountBeforeFees: "0", executedBuyAmount: "0" });
  ports.trades = ports.receipt = () => { throw Error("unexpected provider call"); };
  const result = await reconcileCowOrder(p, ports, () => at);
  assert.equal(result.state, "pending"); assert.equal(result.error, null);
  assert.equal(result.receivedOutputAmountRaw, null);
});
Deno.test("CoW cancelled/expired API status never releases funds or proves zero chain fills", async () => {
  const { prepared: p } = await context();
  for (const status of ["cancelled", "expired"]) {
    const ports = evidence(p);
    ports.order = async () => ({ ...providerOrder(p), status, invalidated: status === "cancelled",
      executedSellAmount: "0", executedSellAmountBeforeFees: "0", executedBuyAmount: "0" });
    const result = await reconcileCowOrder(p, ports, () => at);
    assert.equal(result.state, "unknown"); assert.equal(result.error, "cow_terminal_requires_reconciliation");
    assert.equal(result.resubmitAllowed, false);
  }
});
Deno.test("CoW not found, timeout or private provider error stay unknown without retry or output credit", async () => {
  const { prepared: p } = await context();
  for (const stage of ["order", "trades", "receipt"] as const) {
    const ports = evidence(p); let calls = 0;
    ports[stage] = () => { calls++; throw Error("secret provider detail"); };
    const result = await reconcileCowOrder(p, ports, () => at);
    assert.equal(calls, 1); assert.equal(result.state, "unknown"); assert.equal(result.receivedOutputAmountRaw, null);
    assert.equal(result.error, "cow_reconciliation_unavailable"); assert.ok(!JSON.stringify(result).includes("secret"));
  }
});
Deno.test("CoW API order identity, settlement, hooks, totals and nonpartial constraints are checked", async () => {
  const { prepared: p } = await context();
  for (const patch of [{ uid: "0x" + "11".repeat(56) }, { owner: p.instrument.token }, { receiver: p.instrument.token },
    { settlementContract: p.instrument.token }, { sellToken: p.order.buyToken }, { buyToken: p.order.sellToken },
    { sellAmount: "1" }, { buyAmount: "1" }, { feeAmount: "1" }, { kind: "buy" }, { signingScheme: "ethsign" },
    { validTo: p.order.validTo + 1 }, { partiallyFillable: true }, { buyTokenBalance: "internal" },
    { interactions: { pre: [{ target: owner }], post: [] } }, { appData: "0x" + "ab".repeat(32) },
    { executedSellAmount: "1", executedSellAmountBeforeFees: "1" }, { executedBuyAmount: "1" },
    { executedSellAmountBeforeFees: "1" }, { executedFeeAmount: "1" }, { invalidated: true }]) {
    const ports = evidence(p); ports.order = async () => ({ ...providerOrder(p), ...patch });
    const result = await reconcileCowOrder(p, ports, () => at);
    assert.equal(result.state, "needs_reconciliation"); assert.equal(result.receivedOutputAmountRaw, null);
  }
});
Deno.test("CoW missing, duplicate, wrong-order or mismatched trade rows do not prove fulfillment", async () => {
  const { prepared: p } = await context();
  for (const trades of [[], [...providerTrades(p), ...providerTrades(p)], [{ ...providerTrades(p)[0], orderUid: "foreign" }],
    [{ ...providerTrades(p)[0], txHash: null }], [{ ...providerTrades(p)[0], buyAmount: "1" }]]) {
    const ports = evidence(p); ports.trades = async () => trades;
    assert.equal((await reconcileCowOrder(p, ports, () => at)).state, "needs_reconciliation");
  }
});
Deno.test("CoW missing or not-finalized receipt is pending and cannot fund the return", async () => {
  const { prepared: p } = await context("sell");
  for (const receipt of [null, { ...providerReceipt(p), finalizedBlock: "23999999" }]) {
    const ports = evidence(p); ports.receipt = async () => receipt;
    const result = await reconcileCowOrder(p, ports, () => at);
    assert.equal(result.state, "pending"); assert.equal(result.saleProceedsUsdcRaw, null);
  }
});
Deno.test("CoW receipt reorg, revert, wrong chain/transaction or missing settlement event fail closed", async () => {
  const { prepared: p } = await context();
  for (const patch of [{ canonicalBlockHash: "0x" + "cc".repeat(32) }, { status: "reverted" as const }, { chainId: 57073 },
    { transactionHash: "0x" + "cc".repeat(32) }, { blockNumber: "24000001" }, { logs: [] }]) {
    const ports = evidence(p); ports.receipt = async () => ({ ...providerReceipt(p), ...patch });
    assert.equal((await reconcileCowOrder(p, ports, () => at)).state, "needs_reconciliation");
  }
});
Deno.test("CoW log provenance, duplicates, removed logs and fake emitter cannot credit a fill", async () => {
  const { prepared: p } = await context();
  for (const patch of [{ transactionHash: "0x" + "cc".repeat(32) }, { blockHash: "0x" + "cc".repeat(32) },
    { blockNumber: "24000001" }, { logIndex: 0 }, { removed: true }, { address: p.instrument.token }]) {
    const receipt = providerReceipt(p); Object.assign(receipt.logs[2], patch);
    const ports = evidence(p); ports.receipt = async () => receipt;
    assert.equal((await reconcileCowOrder(p, ports, () => at)).state, "needs_reconciliation");
  }
  const duplicate = providerReceipt(p); duplicate.logs.push({ ...duplicate.logs[2], logIndex: 3 });
  const ports = evidence(p); ports.receipt = async () => duplicate;
  assert.equal((await reconcileCowOrder(p, ports, () => at)).state, "needs_reconciliation");
  const overspend = providerReceipt(p);
  overspend.logs[0] = transfer(p.order.sellToken, owner, p.domain.verifyingContract!, (BigInt(p.order.sellAmount) + 1n).toString(), 0);
  ports.receipt = async () => overspend;
  assert.equal((await reconcileCowOrder(p, ports, () => at)).state, "needs_reconciliation");
});
Deno.test("CoW net receiver credit excludes existing wallet money, unrelated deposits and output immediately spent", async () => {
  const { prepared: p } = await context("sell");
  for (const extra of [transfer(p.order.buyToken, p.domain.verifyingContract!, owner, "1000000", 3),
    transfer(p.order.buyToken, owner, p.domain.verifyingContract!, "1", 3)]) {
    const receipt = providerReceipt(p); receipt.logs.push(extra);
    const ports = evidence(p); ports.receipt = async () => receipt;
    const result = await reconcileCowOrder(p, ports, () => at);
    assert.equal(result.state, "needs_reconciliation"); assert.equal(result.saleProceedsUsdcRaw, null);
  }
  const receipt = providerReceipt(p); receipt.logs[1] = transfer(p.order.buyToken, p.domain.verifyingContract!, p.instrument.token, p.order.buyAmount, 1);
  const ports = evidence(p); ports.receipt = async () => receipt;
  assert.equal((await reconcileCowOrder(p, ports, () => at)).state, "needs_reconciliation");
});
Deno.test("CoW status adapter uses bounded fixed-domain GET and exactly the stored UID, never submit", async () => {
  const { prepared: p } = await context("sell", "Ink"), urls: string[] = [];
  const reader = cowStatusReader(evidence(p).receipt, (async (url, init) => {
    urls.push(String(url)); assert.equal(init?.method, "GET"); assert.equal(init?.redirect, "error"); assert.ok(init?.signal);
    return Response.json(String(url).includes("/trades?") ? providerTrades(p) : providerOrder(p));
  }) as typeof fetch);
  assert.equal((await reconcileCowOrder(p, reader, () => at)).state, "confirmed");
  assert.equal(urls.length, 2); assert.equal(urls[0], `https://api.cow.fi/ink/api/v1/orders/${p.orderUid}`);
  assert.equal(new URL(urls[1]).searchParams.get("orderUid"), p.orderUid);
  assert.equal(new URL(urls[1]).searchParams.get("limit"), "2");
  const failure = cowStatusReader(evidence(p).receipt, (async () => Response.json({ secret: "private" }, { status: 404 })) as typeof fetch);
  const result = await reconcileCowOrder(p, failure, () => at);
  assert.equal(result.state, "unknown"); assert.equal(result.error, "cow_status_unavailable");
});
Deno.test("CoW receipt RPC validates actual chain and reads finalized plus canonical blocks without writes", async () => {
  const { prepared: p } = await context(); const seen: { method: string; params: unknown[] }[] = [];
  const reader = cowReceiptReader({ Ethereum: "https://rpc.test.invalid" }, (async (_url, init) => {
    assert.equal(init?.redirect, "error"); assert.ok(init?.signal);
    const request = JSON.parse(init?.body as string); seen.push(request);
    let result;
    if (request.method === "eth_chainId") result = "0x1";
    else if (request.method === "eth_getTransactionReceipt") result = { transactionHash: hash, transactionIndex: "0x0",
      blockHash, blockNumber: "0x16e3600", from: owner, to: p.domain.verifyingContract, cumulativeGasUsed: "0x1",
      gasUsed: "0x1", effectiveGasPrice: "0x1", contractAddress: null, logs: [], logsBloom: "0x" + "00".repeat(256), status: "0x1", type: "0x2" };
    else if (request.method === "eth_getBlockByNumber") result = { number: request.params[0] === "finalized" ? "0x16e360a" : "0x16e3600", hash: blockHash,
      timestamp: "0x1", transactions: [] };
    else throw Error("unexpected RPC");
    return Response.json({ jsonrpc: "2.0", id: request.id, result });
  }) as typeof fetch);
  const receipt = await reader(p, hash);
  assert.equal(receipt!.finalizedBlock, "24000010"); assert.equal(receipt!.canonicalBlockHash, blockHash);
  assert.deepEqual(seen.map(r => r.method), ["eth_chainId", "eth_getTransactionReceipt", "eth_getBlockByNumber", "eth_getBlockByNumber"]);
  assert.equal(seen[2].params[0], "finalized");
  const wrong = cowReceiptReader({ Ethereum: "https://rpc.test.invalid" }, (async (_url, init) => {
    const r = JSON.parse(init?.body as string); return Response.json({ jsonrpc: "2.0", id: r.id, result: "0xdf11" });
  }) as typeof fetch);
  await assert.rejects(() => wrong(p, hash), /cow_receipt_unavailable/);
});
