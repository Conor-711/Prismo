import { strict as assert } from "node:assert";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { NETWORKS } from "../supabase/functions/bsmart-equities/assets.ts";
import { fundingIntent, fundingPreview } from "../supabase/functions/bsmart-equities/funding_preview.ts";
import { fundingGuard } from "../supabase/functions/bsmart-equities/funding_guard.ts";
import { hypercoreFunds, perpsFunds, spotFunds } from "../supabase/functions/bsmart-equities/hypercore_funds.ts";
import { relayFundingBody, relayFundingQuote, validateRelayFunding } from "../supabase/functions/bsmart-equities/relay_funding.ts";
import { ceilMicro, floorMicro, FUNDING_CURRENCIES as currencies, HC_SPOT, type BridgeRequest, type FundingPorts } from "../supabase/functions/bsmart-equities/funding_types.ts";
import { handleEquities } from "../supabase/functions/bsmart-equities/handler.ts";
import type { IntentRow, Ledger } from "../supabase/functions/bsmart-equities/intents.ts";
import type { EVMCatalogs } from "../supabase/functions/bsmart-equities/routing.ts";
import type { ChainState } from "../supabase/functions/bsmart-equities/quote.ts";
const fixture = JSON.parse(await Deno.readTextFile(new URL("../../../contracts/fixtures/evm-equity-funding.json", import.meta.url)));

const at = Date.parse("2026-10-01T00:00:00Z"), owner = "0x2222222222222222222222222222222222222222";
const account = "12345678-1234-1234-1234-123456789abc", token = "0x1111111111111111111111111111111111111111";
const depository = "0x3333333333333333333333333333333333333333";
const instrument = { assetId: account, symbol: "ASTSx", network: "Ethereum" as const, chainId: 1,
  token, usdc: NETWORKS.Ethereum.usdc, tokenVariant: "raw" as const, maxLeverage: 1 as const };
const catalogs: EVMCatalogs = (() => {
  const asset = { id: account, symbol: "ASTSx", ticker: "ASTS", name: "ASTS", halted: false, tradingHours: null,
    deployments: [{ network: "Ethereum" as const, token, usdc: NETWORKS.Ethereum.usdc, wrapperV2: null }] };
  return { hl: async () => ({ at, values: [] }), registry: async () => ({ at, values: [asset] }), asset: async () => ({ at, values: [asset] }) };
})();
function row(): IntentRow {
  return { id: account, client_intent_id: account, account_id: account, wallet_address: owner, request_hash: "a".repeat(64),
    input: { ticker: "ASTS", side: "buy", amount: "100", slippageBps: 50, maxNetworkFeeBps: 100 }, state: "quoted", version: 1,
    quote_expires_at: new Date(at + 60000).toISOString(), created_at: new Date(at).toISOString(), updated_at: new Date(at).toISOString(),
    preview: { ticker: "ASTS", side: "buy", failures: [], executionEnabled: false, gasCoverage: "unverified",
      defaultSaleProceedsDestination: "hyperliquid_perps", returnTransferImplemented: false, candidates: [{ instrument, owner, receiver: owner,
        inputAmountRaw: "100000000", quotedOutputAmountRaw: "2000000000000000000", minimumOutputAmountRaw: "1900000000000000000",
        estimatedNetworkFeeAmountRaw: "500000", protocolFeeBps: 0, inputDecimals: 6, outputDecimals: 18, balanceRaw: "0", allowanceRaw: "0",
        stateBlock: "100", multiplierRaw: "1000000000000000000", observedAt: new Date(at).toISOString(), expiresAt: new Date(at + 60000).toISOString(),
        providerVerified: false, blockers: ["funding_required", "approval_required", "execution_disabled", "quote_unverified", "gas_sponsorship_unverified"],
        fingerprint: "b".repeat(64), executable: false }] } };
}
const state = (usdc = "20000000"): ChainState => ({ at, chainId: 1, owner, token, usdc: NETWORKS.Ethereum.usdc,
  block: "100", blockTimestamp: at / 1000, tokenDecimals: 18, usdcDecimals: 6, tokenBalance: "10000000000000000000", usdcBalance: usdc,
  tokenAllowance: "0", usdcAllowance: "0", multiplier: "1000000000000000000", multiplierNonce: "0", activationTime: 0 });
function relayResponse(request: BridgeRequest, output?: string) {
  const from = currencies[request.source], to = currencies[request.destination];
  const outputRaw = output ?? String((floorMicro(BigInt(request.amountRaw), from.decimals) - 100000n) * (to.decimals === 8 ? 100n : 1n));
  const c = (n: keyof typeof currencies) => ({ chainId: currencies[n].chainId, address: currencies[n].address, decimals: currencies[n].decimals });
  const refund = (n: keyof typeof currencies) => ({ chainId: currencies[n].protocolChain, currency: currencies[n].address,
    recipient: request.owner, deadline: (at + 600000) / 1000, minimumAmount: "0" });
  const signature = from.chainId === 1337 ? { signatureKind: "eip712", primaryType: "NonceMapping",
    value: { wallet: request.owner, depositor: request.owner, chainId: "hyperliquid", nonce: at, id: "0x" + "a".repeat(64) } } : {
      signatureKind: "eip712", primaryType: "ReceiveWithAuthorization", domain: { chainId: from.chainId, verifyingContract: from.address },
      value: { from: request.owner, to: depository, value: request.amountRaw, validBefore: (at + 60000) / 1000 } };
  const step = (kind: string, data: unknown) => ({ kind, requestId: "0x" + "b".repeat(64), items: [{ status: "incomplete", data }] });
  return { details: { operation: "swap", sender: request.owner, recipient: request.owner,
    currencyIn: { currency: c(request.source), amount: request.amountRaw, minimumAmount: request.amountRaw },
    currencyOut: { currency: c(request.destination), amount: outputRaw, minimumAmount: outputRaw }, refundCurrency: { currency: c(request.source) } },
    fees: { gas: { amount: "0" }, relayer: { amount: "100000" }, relayerGas: { amount: "70000" }, relayerService: { amount: "30000" } },
    protocol: { v2: { paymentDetails: { chainId: from.protocolChain, currency: from.address, amount: request.amountRaw, depository },
      orderData: { inputs: [{ payment: { chainId: from.protocolChain, currency: from.address, amount: request.amountRaw, weight: "1" },
        refunds: [refund(request.source), refund(request.destination)] }], fees: [],
        output: { chainId: to.protocolChain, calls: [], deadline: (at + 600000) / 1000,
          payments: [{ recipient: request.owner, currency: to.address, minimumAmount: outputRaw, expectedAmount: outputRaw }] } } } },
    steps: [step("signature", { sign: signature }), ...(from.chainId === 1337 ? [step("transaction", { nonce: at,
      action: { type: "sendAsset", parameters: { hyperliquidChain: "Mainnet", destination: depository,
        sourceDex: request.source === "HyperCoreSpot" ? "spot" : "", destinationDex: "", token: "USDC:" + HC_SPOT,
        amount: String(Number(request.amountRaw) / 100000000), fromSubAccount: "", nonce: at } } })] : [])] };
}
function ports(usdc = "20000000"): FundingPorts {
  return { state: async () => state(usdc), hypercore: async () => ({ owner, mode: "default", source: "HyperCorePerps",
    availableRaw: "20000000000", at, flatAccountChecked: false }),
    bridge: async req => validateRelayFunding(relayResponse(req), req, at, at), assertIdle: async () => {} };
}
const req: BridgeRequest = { owner, source: "HyperCorePerps", destination: "Ethereum", amountRaw: "10000000000" };

Deno.test("funding precision rounds input cost up and received funds down without floats", () => {
  assert.equal(floorMicro(199n, 8), 1n); assert.equal(ceilMicro(199n, 8), 2n);
  assert.equal(floorMicro(123n, 6), 123n); assert.equal(ceilMicro(123n, 6), 123n);
});
Deno.test("Relay requests are same-owner exact-input quotes only, without deposit address or fee sponsorship", () => {
  const body = relayFundingBody(req);
  assert.equal(body.user, owner); assert.equal(body.recipient, owner); assert.equal(body.refundTo, owner);
  assert.equal(body.protocolVersion, "v2"); assert.equal(body.useDepositAddress, false); assert.equal(body.slippageTolerance, "0");
  assert.equal(Object.hasOwn(body, "subsidizeFees"), false);
  assert.throws(() => relayFundingBody({ ...req, destination: "HyperCorePerps" }));
});
Deno.test("Relay quote binds protocol payments/refunds and does not double-count fee breakdowns", () => {
  const q = validateRelayFunding(relayResponse(req), req, at, at);
  assert.equal(q.maximumLossUsdcRaw, "100000"); assert.equal(q.mechanism, "hypercore_nonce_mapping");
  assert.equal(q.expiresAt, new Date(at + 30000).toISOString());
  assert.deepEqual(q.refundNetworks, ["HyperCorePerps", "Ethereum"]);
  const text = JSON.stringify(q); for (const key of ["typedData", "signature", "nonce", "requestId", "depository"]) assert.equal(text.includes('"' + key + '"'), false);
});
Deno.test("Relay quote rejects changed owner, asset, chain, amount, payments, calls, refunds and nonce", () => {
  const patches = [(r: any) => r.details.recipient = token, (r: any) => r.details.sender = token,
    (r: any) => r.details.currencyIn.currency.decimals = 6, (r: any) => r.details.currencyOut.currency.address = token,
    (r: any) => r.details.currencyIn.amount = "1", (r: any) => r.details.currencyOut.minimumAmount = "0",
    (r: any) => r.protocol.v2.orderData.output.payments[0].recipient = token,
    (r: any) => r.protocol.v2.orderData.output.calls = [{}], (r: any) => r.protocol.v2.orderData.inputs[0].refunds[0].recipient = token,
    (r: any) => r.protocol.v2.orderData.inputs[0].refunds[0].currency = token,
    (r: any) => r.protocol.v2.orderData.inputs.push(r.protocol.v2.orderData.inputs[0]),
    (r: any) => r.steps[1].items[0].data.action.parameters.nonce++, (r: any) => r.steps[1].items[0].data.action.parameters.destination = token];
  for (const patch of patches) { const r = relayResponse(req); patch(r); assert.throws(() => validateRelayFunding(r, req, at, at)); }
});
Deno.test("Relay quote expiry cannot be renewed by reading an old response", () => {
  assert.throws(() => validateRelayFunding(relayResponse(req), req, at, at + 30000));
  const r = relayResponse(req); r.protocol.v2.orderData.output.deadline = (at + 5000) / 1000;
  assert.throws(() => validateRelayFunding(r, req, at, at));
});
Deno.test("return permit shape is indicative only, executor allowlisting is not signing validation", () => {
  const request: BridgeRequest = { owner, source: "Ethereum", destination: "HyperCorePerps", amountRaw: "100000000" };
  const q = validateRelayFunding(relayResponse(request), request, at, at);
  assert.equal(q.mechanism, "permit_candidate"); assert.equal(q.originNativeGasRequired, false);
  const router = relayResponse(request) as any; router.steps[0].items[0].data.sign.value.to = token;
  assert.equal(validateRelayFunding(router, request, at, at).mechanism, "permit_candidate");
  for (const patch of [(r: any) => r.steps[0].items[0].data.sign.domain.chainId = 57073,
    (r: any) => r.steps[0].items[0].data.sign.value.value = "1", (r: any) => r.steps[0].items[0].data.sign.value.to = "0x" + "0".repeat(40)]) {
    const r = relayResponse(request); patch(r); assert.throws(() => validateRelayFunding(r, request, at, at));
  }
});
Deno.test("Relay adapter uses bounded fixed-domain quote-only transport and sanitized failure", async () => {
  const calls: string[] = [];
  const fetcher = async (url: any, init: any) => { calls.push(String(url)); assert.equal(init.redirect, "error");
    assert.equal(init.headers["x-api-key"], "secret"); return Response.json(relayResponse(req)); };
  await relayFundingQuote("secret", fetcher as typeof fetch, () => at)(req);
  assert.deepEqual(calls, ["https://api.relay.link/quote/v2"]);
  await assert.rejects(() => relayFundingQuote(undefined, (async () => Response.json({ error: "secret" }, { status: 400 })) as typeof fetch, () => at)(req),
    (e: any) => e.code === "bridge_quote_unavailable" && !e.message.includes("secret"));
});
Deno.test("execution-chain funds skip HL and bridge; incoming estimates are not added", async () => {
  const p = ports("100000000"); p.hypercore = p.bridge = async () => { throw Error("unexpected funding call"); };
  const result = await fundingPreview(row(), owner, catalogs, p, () => at);
  assert.equal(result.plans[0].source, "execution_chain"); assert.equal(result.plans[0].bridge, null);
  assert.equal(result.plans[0].deficitUsdcRaw, "0"); assert.equal(result.executionEnabled, false);
  assert.equal(result.reservationsImplemented, false);
});
Deno.test("buy deficit uses bounded HL funds, covers minimum output and caps combined quoted cost", async () => {
  const result = await fundingPreview(row(), owner, catalogs, ports(), () => at), plan = result.plans[0];
  assert.deepEqual(result, fixture.response);
  assert.equal(plan.deficitUsdcRaw, "80000000"); assert.equal(plan.bridge!.inputAmountRaw, "8050000000");
  assert.equal(plan.bridge!.minimumOutputAmountRaw, "80400000"); assert.equal(plan.costBoundUsdcRaw, "600000");
  assert.equal(plan.blockers.includes("funding_authorization_required"), true);
  assert.equal(plan.blockers.includes("quote_unverified"), true);
});
Deno.test("funding refuses insufficient balance/output and native gas requirement", async () => {
  for (const [error, patch] of [
    ["funding_insufficient_balance", (p: FundingPorts) => p.hypercore = async () => ({ owner, mode: "default", source: "HyperCorePerps", at, availableRaw: "1", flatAccountChecked: false })],
    ["funding_insufficient_output", (p: FundingPorts) => p.bridge = async q => validateRelayFunding(relayResponse(q, "79999999"), q, at, at)],
    ["bridge_native_gas_required", (p: FundingPorts) => { const bridge = p.bridge; p.bridge = async q => ({ ...await bridge(q), originNativeGasRequired: true }); }],
  ] as const) {
    const p = ports(); patch(p);
    const result = await fundingPreview(row(), owner, catalogs, p, () => at);
    assert.equal(result.plans.length, 0); assert.equal(result.failures.length, 1);
    assert.equal(result.failures[0].error, error);
  }
});
Deno.test("balance change during provider response never yields a plan", async () => {
  const p = ports(); let reads = 0; p.state = async () => state(++reads === 1 ? "20000000" : "19999999");
  const result = await fundingPreview(row(), owner, catalogs, p, () => at);
  assert.equal(result.plans.length, 0); assert.equal(result.failures[0].error, "funding_balance_changed");
});
Deno.test("HL balance shrink or mode switch after quote never yields a plan", async () => {
  const p = ports(); let reads = 0;
  p.hypercore = async () => ({ owner, mode: "default", source: "HyperCorePerps", at, availableRaw: ++reads === 1 ? "20000000000" : "0", flatAccountChecked: false });
  const result = await fundingPreview(row(), owner, catalogs, p, () => at);
  assert.equal(result.failures[0].error, "hypercore_funds_changed");
});
Deno.test("sell return estimates only minimum sale proceeds and keeps old xStocks exit after HL listing", async () => {
  const r = row(); r.input = { ...r.input, side: "sell", amount: "2" }; r.preview!.side = "sell";
  Object.assign(r.preview!.candidates[0], { inputAmountRaw: "2000000000000000000", minimumOutputAmountRaw: "100000000", inputDecimals: 18, outputDecimals: 6 });
  const p = ports("500000000"); p.hypercore = async () => { throw Error("unexpected"); };
  const result = await fundingPreview(r, owner, { ...catalogs, hl: async () => ({ at, values: [{ coin: "ASTS", dex: "", collateralToken: 0, maxLeverage: 10, delisted: false }] }) }, p, () => at);
  assert.equal(result.plans[0].bridge!.inputAmountRaw, "100000000"); assert.equal(result.plans[0].bridge!.destination, "HyperCorePerps");
  assert.equal(result.plans[0].saleProceedsBasis, "quoted_minimum"); assert.equal(result.returnTransferImplemented, false);
  assert.equal(result.plans[0].blockers.includes("fresh_return_quote_required"), true);
  assert.equal(result.plans[0].blockers.includes("permit_executor_unverified"), true);
});
Deno.test("expired previews, switched wallet or unquoted intents fail before provider work", () => {
  assert.throws(() => fundingIntent(row(), token, 1, at)); assert.throws(() => fundingIntent(row(), owner, 0, at));
  assert.throws(() => fundingIntent({ ...row(), state: "draft" }, owner, 1, at));
  assert.throws(() => fundingIntent({ ...row(), quote_expires_at: "invalid" }, owner, 1, at));
  assert.throws(() => fundingIntent(row(), owner, 1, at + 55000));
});
Deno.test("cost ceiling blocks expensive CoW costs and expensive return, even with adequate balances", async () => {
  const buy = row(); buy.preview!.candidates[0].estimatedNetworkFeeAmountRaw = "1000001";
  assert.equal((await fundingPreview(buy, owner, catalogs, ports("100000000"), () => at)).failures[0].error, "funding_fee_limit");
  const sell = row(); sell.input = { ...sell.input, side: "sell", amount: "2" }; sell.preview!.side = "sell";
  Object.assign(sell.preview!.candidates[0], { inputAmountRaw: "2000000000000000000", minimumOutputAmountRaw: "100000000", inputDecimals: 18, outputDecimals: 6 });
  const p = ports(); p.bridge = async q => validateRelayFunding(relayResponse(q, "9899999900"), q, at, at);
  assert.equal((await fundingPreview(sell, owner, catalogs, p, () => at)).failures[0].error, "funding_fee_limit");
});
Deno.test("a newly listed HL market blocks a buy before funding providers", async () => {
  const p = ports(); p.state = async () => { throw Error("unexpected state"); };
  await assert.rejects(() => fundingPreview(row(), owner, { ...catalogs,
    hl: async () => ({ at, values: [{ coin: "ASTS", dex: "", collateralToken: 0, maxLeverage: 10, delisted: false }] }) }, p, () => at),
    (e: any) => e.code === "xstocks_route_required");
});
Deno.test("HL parsers never use equity as spendable and reject malformed/held USDC", () => {
  assert.equal(perpsFunds({ withdrawable: "3.12345678", marginSummary: { accountValue: "999" }, time: at }, at), "312345678");
  assert.throws(() => perpsFunds({ withdrawable: "3.123456789", time: at }, at));
  assert.throws(() => perpsFunds({ withdrawable: "-1", time: at }, at));
  assert.throws(() => perpsFunds({ withdrawable: "1", time: at - 30000 }, at));
  assert.equal(spotFunds({ balances: [] }), "0");
  assert.equal(spotFunds({ balances: [{ token: 0, coin: "USDC", total: "1", hold: "0" }] }), "100000000");
  for (const balances of [[{ token: 0, coin: "USDC", total: "1", hold: "0.1" }], [{ token: 1, coin: "USDC" }],
    [{ token: 0, coin: "USDC", total: "1", hold: "0" }, { token: 0, coin: "USDC", total: "1", hold: "0" }]]) assert.throws(() => spotFunds({ balances }));
});
function hlFetcher(mode = "default", patches: Record<string, unknown> = {}, calls: string[] = []) {
  return (async (_url: any, init: any) => {
    const b = JSON.parse(init.body); calls.push(b.type + ":" + (b.dex ?? ""));
    const value = Object.hasOwn(patches, b.type) ? patches[b.type] : b.type === "userAbstraction" ? mode :
      b.type === "perpDexs" ? [null, { name: "xyz" }] : b.type === "openOrders" ? [] :
      b.type === "spotClearinghouseState" ? { balances: [{ token: 0, coin: "USDC", total: "10", hold: "0" }] } :
      { withdrawable: "5", time: at, assetPositions: [] };
    return Response.json(value);
  }) as typeof fetch;
}
Deno.test("unified HL requires every venue flat and mode stable; never sums shared perps balance", async () => {
  const calls: string[] = [], q = await hypercoreFunds(hlFetcher("unifiedAccount", {}, calls), () => at)(owner);
  assert.equal(q.source, "HyperCoreSpot"); assert.equal(q.availableRaw, "1000000000"); assert.equal(q.flatAccountChecked, true);
  assert.equal(calls.includes("openOrders:xyz"), true); assert.equal(calls.includes("clearinghouseState:xyz"), true);
  await assert.rejects(() => hypercoreFunds(hlFetcher("unifiedAccount", { openOrders: [{}] }), () => at)(owner));
  await assert.rejects(() => hypercoreFunds(hlFetcher("unifiedAccount", { clearinghouseState: {} }), () => at)(owner));
  await assert.rejects(() => hypercoreFunds(hlFetcher("portfolioMargin"), () => at)(owner));
  let n = 0; const f = hlFetcher();
  await assert.rejects(() => hypercoreFunds((async (url: any, init: any) => JSON.parse(init.body).type === "userAbstraction"
    ? Response.json(++n === 1 ? "default" : "unifiedAccount") : f(url, init)) as typeof fetch, () => at)(owner));
});
Deno.test("wallet-wide inflight guard checks three ledgers, fails closed on database error", async () => {
  const tables: string[] = [], filters: any[] = [];
  const client = (busy = false, broken = false) => ({ from: (table: string) => { tables.push(table);
    const q = { select() { return this; }, eq(k: string, v: string) { filters.push([k, v]); return this; }, neq() { return this; },
      in() { return this; }, limit: async () => ({ data: busy ? [{ id: account }] : [], error: broken ? { message: "secret" } : null }) }; return q; } }) as unknown as SupabaseClient;
  await fundingGuard(client())(account, owner, account);
  assert.deepEqual(tables, ["bsmart_across_withdrawals", "bsmart_withdrawals", "bsmart_equity_intents"]);
  assert.equal(filters.some(x => x[0] === "account_id"), false);
  await assert.rejects(() => fundingGuard(client(true))(account, owner, account), (e: any) => e.code === "funding_activity_in_progress");
  await assert.rejects(() => fundingGuard(client(false, true))(account, owner, account), (e: any) => e.code === "funding_state_unavailable");
});
Deno.test("funding preview rechecks inflight guard after balance/quote reads", async () => {
  const p = ports("100000000"); let n = 0; p.assertIdle = async () => { if (++n === 2) throw Error("blocked"); };
  await assert.rejects(() => fundingPreview(row(), owner, catalogs, p, () => at));
});
Deno.test("funding HTTP gate, strict request, account isolation and late cancel cause no mutation", async () => {
  let current = row(), writes = 0;
  const ledger: Ledger = { get: async () => structuredClone(current), legs: async () => [],
    create: async () => { throw Error(); }, change: async () => { writes++; throw Error(); } };
  const client = { auth: { getUser: async () => ({ data: { user: { id: account, identities: [{ provider: "apple" }] } }, error: null }) },
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { address: owner }, error: null }) }) }) }) } as unknown as SupabaseClient;
  const request = (body: unknown = { expectedVersion: 1 }) => new Request("https://test.invalid/bsmart-equities/intents/" + account + "/funding-preview",
    { method: "POST", headers: { authorization: "Bearer a.b.c", "content-type": "application/json" }, body: JSON.stringify(body) });
  const opts = { catalogs, discoveryEnabled: false, ledgerEnabled: true, ledger, fundingPorts: ports("100000000"), now: () => at };
  assert.equal((await handleEquities(request(), client, opts)).status, 503);
  const enabled = { ...opts, fundingPreviewEnabled: true };
  assert.equal((await handleEquities(request({ expectedVersion: 1, owner }), client, enabled)).status, 422);
  assert.equal((await handleEquities(request(), client, enabled)).status, 200);
  current = { ...row(), account_id: "98765432-1234-1234-1234-123456789abc" };
  assert.equal((await handleEquities(request(), client, enabled)).status, 404);
  current = row(); const read = enabled.fundingPorts.state;
  enabled.fundingPorts.state = async (...args) => { current = { ...current, state: "cancelled", version: 2 }; return read(...args); };
  assert.equal((await handleEquities(request(), client, enabled)).status, 409);
  assert.equal(writes, 0);
});
