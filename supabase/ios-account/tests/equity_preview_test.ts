import { strict as assert } from "node:assert";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { decodeFunctionData, encodeFunctionResult, erc20Abi, parseAbi } from "npm:viem@2.56.3";
import { OrderSigningUtils } from "npm:@cowprotocol/sdk-order-signing@1.1.15";
import { NETWORKS, type Asset } from "../supabase/functions/bsmart-equities/assets.ts";
import { APP_DATA, atoms, type ChainState, previewInput, type PreviewInput, quoteRequest, raw, validateQuote, validateState } from "../supabase/functions/bsmart-equities/quote.ts";
import { type EVMCatalogs, type EVMInstrument } from "../supabase/functions/bsmart-equities/routing.ts";
import { previewEquity, previewEquityArtifacts, type PreviewPorts } from "../supabase/functions/bsmart-equities/preview.ts";
import { cowQuote } from "../supabase/functions/bsmart-equities/cow.ts";
import { chainReader } from "../supabase/functions/bsmart-equities/chain.ts";
import { handleEquities } from "../supabase/functions/bsmart-equities/handler.ts";

const at = Date.parse("2026-10-01T00:00:00Z"), now = () => at;
const owner = "0x2222222222222222222222222222222222222222", token = "0x1111111111111111111111111111111111111111";
const account = "12345678-1234-1234-1234-123456789abc";
const instrument: EVMInstrument = { assetId: account, symbol: "ASTSx", network: "Ethereum", chainId: 1,
  token, usdc: NETWORKS.Ethereum.usdc, tokenVariant: "raw", maxLeverage: 1 };
const input: PreviewInput = { ticker: "ASTS", side: "buy", amount: "100", slippageBps: 50, maxNetworkFeeBps: 100 };
const state = (i = instrument): ChainState => ({ at, chainId: i.chainId, owner, token: i.token, usdc: i.usdc,
  block: "24000000", blockTimestamp: at / 1000 - 12, tokenDecimals: 18, usdcDecimals: 6,
  tokenBalance: "3000000000000000000", usdcBalance: "100000000", tokenAllowance: "0", usdcAllowance: "0",
  multiplier: "1100000000000000000", multiplierNonce: "1", activationTime: 0 });
function result(request = quoteRequest(instrument, owner, input, state(), at)) {
  const { sellToken, buyToken, receiver, validTo, appData, kind, sellTokenBalance, buyTokenBalance, signingScheme } = request;
  return { from: owner, expiration: new Date(at + 60_000).toISOString(), id: 123, verified: false,
    quote: { sellToken, buyToken, receiver, validTo, appData, kind, sellTokenBalance, buyTokenBalance, signingScheme,
      sellAmount: (BigInt(request.sellAmountBeforeFee) - 500000n).toString(), feeAmount: "500000",
      buyAmount: "2000000000000000000", partiallyFillable: false } };
}
function catalogs(listed = false, ticker = "ASTS"): EVMCatalogs {
  const asset: Asset = { id: account, ticker, symbol: ticker + "x", name: ticker, halted: false, tradingHours: "TwentyFourFive",
    deployments: [{ network: "Ethereum", token, wrapperV2: null, usdc: instrument.usdc }] };
  return { hl: async () => ({ at, values: listed ? [{ coin: "xyz:ASTS", dex: "xyz", collateralToken: 0, maxLeverage: 10, delisted: false }] : [] }),
    registry: async () => ({ at, values: [asset] }), asset: async () => ({ at, values: [asset] }) };
}
const ports = (): PreviewPorts => ({ state: async i => state(i), quote: async (_i, r) => result(r) });
function client(bound = owner) {
  let selected: string | undefined;
  const c = { auth: { getUser: async () => ({ data: { user: { id: account, is_anonymous: false, identities: [{ provider: "apple" }] } }, error: null }) },
    from: (table: string) => { assert.equal(table, "bsmart_wallets"); return {
      select: (columns: string) => { assert.equal(columns, "address"); return {
        eq: (column: string, value: string) => { assert.equal(column, "account_id"); selected = value; return {
          maybeSingle: async () => ({ data: bound ? { address: bound } : null, error: null }),
        }; },
      }; },
    }; } } as unknown as SupabaseClient;
  return { c, selected: () => selected };
}
const httpRequest = (body: unknown = input, path = "preview") => new Request("https://test.invalid/bsmart-equities/" + path, {
  method: "POST", headers: { authorization: "Bearer a.b.c", "content-type": "application/json" }, body: JSON.stringify(body),
});
Deno.test("equity private canonical artifacts share route, rebase and expiry checks without reaching HTTP", async () => {
  const artifact = await previewEquityArtifacts(input, account, owner, catalogs(), ports(), now);
  assert.deepEqual(artifact.preview, await previewEquity(input, account, owner, catalogs(), ports(), now));
  assert.equal(artifact.materials.length, 1); assert.equal(artifact.materials[0].account, account);
  assert.equal(artifact.materials[0].order.buyAmount, artifact.preview.candidates[0].minimumOutputAmountRaw);
  assert.equal(Object.hasOwn(artifact.preview, "materials"), false);
  await assert.rejects(() => previewEquityArtifacts(input, account, owner, catalogs(true), ports(), now));
});

Deno.test("equity preview accepts exact intent fields only, not owner, chain, raw address or signature", () => {
  assert.deepEqual(previewInput(input), input);
  for (const extra of ["owner", "receiver", "token", "chainId", "network", "appData", "signature", "feeAmount", "partiallyFillable"]) {
    assert.throws(() => previewInput({ ...input, [extra]: "untrusted" }));
  }
  for (const v of [null, [], {}, { ...input, amount: 100 }, { ...input, side: "short" }, { ...input, slippageBps: 1001 },
    { ...input, amount: "1e2" }, { ...input, amount: "00.1" }, { ...input, amount: "0" }, { ...input, minimumOutput: "0.000" }]) assert.throws(() => previewInput(v));
});
Deno.test("equity amounts never round fractional atoms and enforce uint256", () => {
  assert.equal(atoms("100.000001", 6), "100000001");
  assert.equal(atoms("0.000000000000000001", 18), "1");
  for (const s of ["0.0000001", "1.0000000"]) assert.throws(() => atoms(s, 6));
  for (const s of [String(2n ** 256n), "-1", "01", "1e10", "1.1"]) assert.throws(() => raw(s));
  assert.equal(raw((2n ** 256n - 1n).toString()), (2n ** 256n - 1n).toString());
});
Deno.test("equity chain snapshots reject stale, wrong identity, decimals and rebase windows", () => {
  validateState(state(), instrument, owner, at);
  for (const patch of [{ at: at + 1 }, { at: at - 30000 }, { owner: token }, { chainId: 57073 }, { token: owner },
    { usdcDecimals: 18 }, { tokenDecimals: 19 }, { blockTimestamp: at / 1000 - 121 }, { multiplier: "0" },
    { activationTime: at / 1000 + 1000 }, { activationTime: at / 1000 - 899 }]) {
    assert.throws(() => validateState({ ...state(), ...patch }, instrument, owner, at));
  }
});
Deno.test("equity buy is fee-inclusive USDC, sell uses adjusted balance units without another multiplier", () => {
  const buy = quoteRequest(instrument, owner, input, state(), at);
  assert.equal(buy.sellToken, instrument.usdc); assert.equal(buy.buyToken, token); assert.equal(buy.sellAmountBeforeFee, "100000000");
  assert.equal(buy.from, owner); assert.equal(buy.receiver, owner); assert.equal(buy.kind, "sell");
  const sell = quoteRequest(instrument, owner, { ...input, side: "sell", amount: "3" }, state(), at);
  assert.equal(sell.sellAmountBeforeFee, state().tokenBalance); assert.equal(sell.sellToken, token); assert.equal(sell.buyToken, instrument.usdc);
  assert.throws(() => quoteRequest(instrument, owner, { ...input, side: "sell", amount: "3.1" }, state(), at));
  assert.throws(() => quoteRequest(instrument, owner, { ...input, amount: "100001" }, state(), at));
});
Deno.test("equity SDK quote math, domain and fingerprint preserve budget and minimum, never expose signed order", async () => {
  const fixture = JSON.parse(await Deno.readTextFile(new URL("../../../contracts/fixtures/evm-equity-preview.json", import.meta.url)));
  const r = quoteRequest(instrument, owner, input, state(), at);
  const preview = await validateQuote(result(r), r, instrument, input, state(), account, at);
  assert.equal(preview.inputAmountRaw, fixture.sdkAmountsExample.inputAmountRaw);
  assert.equal(preview.minimumOutputAmountRaw, fixture.sdkAmountsExample.minimumOutputAmountRaw);
  assert.equal(preview.estimatedNetworkFeeAmountRaw, "500000"); assert.equal(preview.executable, false);
  assert.deepEqual(preview.blockers, ["approval_required", "quote_unverified", "execution_disabled", "gas_sponsorship_unverified"]);
  assert.match(preview.fingerprint, /^[0-9a-f]{64}$/);
  for (const key of ["order", "domain", "typedData", "signature", "transaction"]) assert.equal(Object.hasOwn(preview, key), false);
  const again = await validateQuote(result(r), r, instrument, input, state(), account, at);
  assert.equal(preview.fingerprint, again.fingerprint);
  const different = await validateQuote(result(r), r, instrument, input, state(), "different-account", at);
  assert.notEqual(preview.fingerprint, different.fingerprint);
  const changedFee = result(r); changedFee.quote.sellAmount = "99750000"; changedFee.quote.feeAmount = "250000";
  const feeBinding = await validateQuote(changedFee, r, instrument, input, state(), account, at);
  assert.notEqual(preview.fingerprint, feeBinding.fingerprint);
  for (const id of [1, 57073]) assert.equal((await OrderSigningUtils.getDomain(id)).chainId, id);
});
Deno.test("equity response substitution, partial fills, balance modes and expiration are rejected", async () => {
  const r = quoteRequest(instrument, owner, input, state(), at);
  for (const patch of [{ sellToken: token }, { buyToken: instrument.usdc }, { receiver: token }, { receiver: null },
    { kind: "buy" }, { partiallyFillable: true }, { sellTokenBalance: "internal" }, { buyTokenBalance: "internal" },
    { appData: "0x" + "11".repeat(32) }, { appDataHash: "0x" + "11".repeat(32) }, { signingScheme: "presign" },
    { validTo: r.validTo + 1 }, { sellAmount: "100000000" }, { buyAmount: "0" }, { feeAmount: "-1" }]) {
    const bad = result(r); Object.assign(bad.quote, patch);
    await assert.rejects(() => validateQuote(bad, r, instrument, input, state(), account, at));
  }
  for (const patch of [{ from: token }, { verified: null }, { id: 0.1 }, { expiration: "never" },
    { expiration: new Date(at + 4999).toISOString() }, { expiration: new Date(at + 600001).toISOString() }, { protocolFeeBps: "10000" }]) {
    await assert.rejects(() => validateQuote({ ...result(r), ...patch }, r, instrument, input, state(), account, at));
  }
});
Deno.test("equity network fee limit is exact and independent of research screening, output floor strengthens slippage", async () => {
  const r = quoteRequest(instrument, owner, input, state(), at);
  await validateQuote(result(r), r, instrument, { ...input, maxNetworkFeeBps: 50 }, state(), account, at);
  await assert.rejects(() => validateQuote(result(r), r, instrument, { ...input, maxNetworkFeeBps: 49 }, state(), account, at));
  const p = await validateQuote(result(r), r, instrument, { ...input, minimumOutput: "1.995" }, state(), account, at);
  assert.equal(p.minimumOutputAmountRaw, "1995000000000000000");
  await assert.rejects(() => validateQuote(result(r), r, instrument, { ...input, minimumOutput: "2.001" }, state(), account, at));
  const unfunded = await validateQuote(result(r), r, instrument, input, { ...state(), usdcBalance: "0" }, account, at);
  assert.ok(unfunded.blockers.includes("funding_required"));
  const verified = await validateQuote({ ...result(r), verified: true }, r, instrument, input, state(), account, at);
  assert.equal(verified.executable, false); assert.ok(verified.blockers.includes("gas_sponsorship_unverified"));
});
Deno.test("equity preview buys obey HL priority but owned sells survive later listings and inventory exclusions", async () => {
  const p = ports(); p.quote = async () => { throw Error("must not quote HL buy"); };
  await assert.rejects(() => previewEquity(input, account, owner, catalogs(true), p, now));
  const sell = { ...input, side: "sell" as const, amount: "1" };
  const output = await previewEquity(sell, account, owner, catalogs(true), ports(), now);
  assert.equal(output.candidates.length, 1); assert.equal(output.returnTransferImplemented, false);
  const outside = await previewEquity({ ...sell, ticker: "OUST" }, account, owner, catalogs(false, "OUST"), ports(), now);
  assert.equal(outside.candidates[0].instrument.symbol, "OUSTx");
  const noPosition = ports(); noPosition.state = async () => ({ ...state(), tokenBalance: "0" });
  noPosition.quote = async () => { throw Error("no quote without owned token"); };
  await assert.rejects(() => previewEquity(sell, account, owner, catalogs(true), noPosition, now));
});
Deno.test("equity preview rechecks rebase, ownership, issuer and HL after quotes", async () => {
  const p = ports(); let reads = 0;
  p.state = async () => ({ ...state(), multiplier: reads++ ? "1200000000000000000" : state().multiplier });
  await assert.rejects(() => previewEquity(input, account, owner, catalogs(), p, now));
  reads = 0; p.state = async () => ({ ...state(), tokenBalance: reads++ ? "0" : state().tokenBalance });
  await assert.rejects(() => previewEquity({ ...input, side: "sell", amount: "1" }, account, owner, catalogs(), p, now));
  const c = catalogs(); let hlReads = 0;
  c.hl = async () => ({ at, values: hlReads++ ? [{ coin: "xyz:ASTS", dex: "xyz", collateralToken: 0, maxLeverage: 10, delisted: false }] : [] });
  await assert.rejects(() => previewEquity(input, account, owner, c, ports(), now));
  const drift = catalogs(); let detailReads = 0, original = drift.asset;
  drift.asset = async s => { const d = await original(s); if (detailReads++) d.values[0].halted = true; return d; };
  await assert.rejects(() => previewEquity(input, account, owner, drift, ports(), now));
});
Deno.test("equity candidate failure does not hide another chain or authorize an expired survivor", async () => {
  const c = catalogs(), original = c.registry;
  const both = async () => { const d = structuredClone(await original()); d.values[0].deployments.push({ network: "Ink", token, wrapperV2: null, usdc: NETWORKS.Ink.usdc }); return d; };
  c.registry = both; c.asset = both;
  const p = ports(); p.state = async i => { if (i.network === "Ink") throw Error("private RPC error body"); return state(i); };
  const output = await previewEquity(input, account, owner, c, p, now);
  assert.equal(output.candidates.length, 1); assert.equal(output.candidates[0].instrument.network, "Ethereum");
  assert.deepEqual(output.failures, [{ network: "Ink", error: "preview_unavailable" }]);
  let time = at;
  const stale = catalogs(); stale.hl = async () => ({ at: time, values: [] });
  const rp = ports(); rp.quote = async (_i, r) => { const q = result(r); time += 61_000; return q; };
  rp.state = async () => ({ ...state(), at: time, blockTimestamp: time / 1000 - 12 });
  stale.asset = async () => { const a = await catalogs().asset("ASTSx"); return { ...a, at: time }; };
  await assert.rejects(() => previewEquity(input, account, owner, stale, rp, () => time));
});
Deno.test("equity CoW transport is fixed-domain bounded quote-only POST, no submit and no retries", async () => {
  let calls = 0;
  const q = cowQuote((async (url, init) => {
    calls++; assert.equal(String(url), "https://api.cow.fi/mainnet/api/v1/quote");
    assert.equal(init?.method, "POST"); assert.equal(init?.redirect, "error"); assert.ok(init?.signal);
    const body = JSON.parse(init?.body as string); assert.equal(body.appData, APP_DATA); assert.equal(body.from, owner);
    return Response.json(result());
  }) as typeof fetch);
  await q(instrument, quoteRequest(instrument, owner, input, state(), at)); assert.equal(calls, 1);
  const failure = cowQuote((async () => { calls++; return Response.json({ description: "secret provider detail" }, { status: 503 }); }) as typeof fetch);
  await assert.rejects(() => failure(instrument, quoteRequest(instrument, owner, input, state(), at)), /cow_quote_unavailable/);
  assert.equal(calls, 2);
});
Deno.test("equity HTTP preview binds real account owner, gates before reads, bounds body and forbids execution", async () => {
  const c = client(); const opts = { catalogs: catalogs(), discoveryEnabled: true, previewEnabled: true, previewPorts: ports(), now };
  let r = await handleEquities(httpRequest(), c.c, opts);
  assert.equal(r.status, 200); assert.equal(c.selected(), account);
  const v = await r.json(); assert.equal(v.candidates[0].owner, owner); assert.equal(v.executionEnabled, false);
  assert.equal(r.headers.get("cache-control"), "no-store");
  r = await handleEquities(httpRequest(), c.c, { ...opts, previewEnabled: false }); assert.equal(r.status, 503);
  r = await handleEquities(httpRequest({ ...input, owner: token }), c.c, opts); assert.equal(r.status, 422);
  r = await handleEquities(httpRequest("x".repeat(4096)), c.c, opts); assert.equal(r.status, 413);
  r = await handleEquities(httpRequest(null), c.c, opts); assert.equal(r.status, 422);
  r = await handleEquities(httpRequest(input, "preview?chainId=1"), c.c, opts); assert.equal(r.status, 422);
  r = await handleEquities(httpRequest(), client("").c, opts); assert.equal(r.status, 503);
  for (const path of ["orders", "approve", "sign", "submit", "transfer"]) {
    assert.equal((await handleEquities(httpRequest(input, path), c.c, opts)).status, 404);
  }
});
Deno.test("equity RPC reader pins one real block, validates chain and reads adjusted balance with official relayer", async () => {
  const rebasing = parseAbi(["function getCurrentMultiplier() view returns (uint256,uint256,uint256)", "function newMultiplierActivationTime() view returns (uint256)"]);
  const blocks = new Set<string>();
  const fetcher = (async (_url, init) => {
    const r = JSON.parse(init?.body as string); let response: unknown;
    if (r.method === "eth_chainId") response = "0x1";
    else if (r.method === "eth_getBlockByNumber") response = { number: "0x16e3600", timestamp: "0x" + (at / 1000 - 12).toString(16), hash: "0x" + "11".repeat(32), transactions: [] };
    else if (r.method === "eth_call") {
      blocks.add(r.params[1]); const contract = r.params[0].to.toLowerCase();
      let decoded;
      try { decoded = decodeFunctionData({ abi: erc20Abi, data: r.params[0].data }); }
      catch { decoded = decodeFunctionData({ abi: rebasing, data: r.params[0].data }); }
      const name = decoded.functionName;
      if (name === "decimals") response = encodeFunctionResult({ abi: erc20Abi, functionName: name, result: contract === token ? 18 : 6 });
      else if (name === "getCurrentMultiplier") response = encodeFunctionResult({ abi: rebasing, functionName: name, result: [1100000000000000000n, 0n, 1n] });
      else if (name === "newMultiplierActivationTime") response = encodeFunctionResult({ abi: rebasing, functionName: name, result: 0n });
      else if (name === "balanceOf" || name === "allowance") {
        assert.equal(decoded.args?.[0]?.toString().toLowerCase(), owner);
        if (name === "allowance") assert.equal(decoded.args?.[1]?.toString().toLowerCase(), "0xc92e8bdf79f0507f65a392b0ab4667716bfe0110");
        response = encodeFunctionResult({ abi: erc20Abi, functionName: name, result: 3000000000000000000n });
      } else throw Error("unexpected RPC operation");
    } else throw Error("mutation attempted");
    return Response.json({ jsonrpc: "2.0", id: r.id, result: response });
  }) as typeof fetch;
  const s = await chainReader({ Ethereum: "https://rpc.invalid" }, now, fetcher)(instrument, owner);
  assert.equal(s.multiplier, "1100000000000000000"); assert.equal(s.tokenBalance, "3000000000000000000");
  assert.equal(s.tokenDecimals, 18); assert.equal(blocks.size, 1); assert.equal(s.block, "24000000");
  const wrongChain = (async () => Response.json({ jsonrpc: "2.0", id: 1, result: "0x2" })) as typeof fetch;
  await assert.rejects(() => chainReader({ Ethereum: "https://rpc.invalid" }, now, wrongChain)(instrument, owner), /chain_state_unavailable/);
  const urls = new Set<string>();
  const fallbackFetcher = (async (url, init) => {
    urls.add(String(url));
    if (String(url).includes("rpc-qnd")) return Response.json({}, { status: 503 });
    const rpc = JSON.parse(init?.body as string);
    if (rpc.method === "eth_chainId") return Response.json({ jsonrpc: "2.0", id: rpc.id, result: "0x" + (57073).toString(16) });
    return await fetcher(url, init);
  }) as typeof fetch;
  const onInk = { ...instrument, network: "Ink" as const, chainId: 57073, usdc: NETWORKS.Ink.usdc };
  assert.equal((await chainReader({}, now, fallbackFetcher)(onInk, owner)).chainId, 57073);
  assert.equal(urls.size, 2);
});
