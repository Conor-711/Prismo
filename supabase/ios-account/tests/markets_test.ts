import { strict as assert } from "node:assert";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { amountInput, Catalogs, dexNames, MarketError, parseHL, parseXStocks, resolveRoute, tickerInput, USDC_MINT } from "../supabase/functions/bsmart-markets/routing.ts";
import { catalogCache, preview, providers, readJSON } from "../supabase/functions/bsmart-markets/providers.ts";
import { handleMarkets } from "../supabase/functions/bsmart-markets/handler.ts";

const at = Date.parse("2026-10-01T00:00:00Z"), now = () => at;
const mint = "Xs8kHDEs5w8ERuTmefBXsJy66G5mh836VgDFfgpuRej";
const rawStock = () => ({ id: "12345678-1234-1234-1234-123456789abc", symbol: "AEHRx", isTradingHalted: false,
  underlying: { symbol: "AEHR", currency: "USD", type: null, exchange: null },
  trading: null, deployments: [{ network: "Solana", address: mint }] });
const market = (coin = "xyz:AAPL", collateralToken = 0, delisted = false) => ({ coin, dex: coin.split(":")[0], collateralToken, maxLeverage: 20, delisted });
function catalogs(values = [market()]): Catalogs {
  return { hl: async () => ({ at, values }), xstocks: async () => ({ at, values: parseXStocks([rawStock()]) }),
    xstock: async () => ({ at, values: parseXStocks([rawStock()]) }) };
}
const fetchJSON = (value: unknown, status = 200) => Promise.resolve(Response.json(value, { status }));
const client = (anonymous = false, provider = "apple") => ({ auth: { getUser: async () => ({ data: {
  user: { id: crypto.randomUUID(), is_anonymous: anonymous, identities: [{ provider }] },
}, error: null }) } } as unknown as SupabaseClient);
const request = (path: string, method = "GET", authorization = "Bearer a.b.c") => new Request("https://test.invalid/bsmart-markets/" + path, { method, headers: { authorization } });

Deno.test("markets inputs retain exact USDC integer precision and reject ambiguous queries", () => {
  assert.equal(tickerInput("brk.b"), "BRK.B");
  assert.equal(amountInput("0.000001"), "1"); assert.equal(amountInput("1.663379"), "1663379");
  assert.equal(amountInput("100000"), "100000000000");
  for (const value of [null, "", "0", "00.1", "+1", "1e3", "1.0000001", "100000.000001", "999999", " 1"]) assert.throws(() => amountInput(value));
  for (const value of [null, " AAPL", "xyz:AAPL", "A/B", "A".repeat(17)]) assert.throws(() => tickerInput(value));
});
Deno.test("markets full HL parser rejects partial catalogs, duplicate coins and unknown metadata", () => {
  const dexes = dexNames([null, { name: "xyz" }]);
  const metas = [{ collateralToken: 0, universe: [{ name: "BTC", maxLeverage: 40 }] },
    { collateralToken: 0, universe: [{ name: "xyz:AAPL", maxLeverage: 20 }] }];
  assert.equal(parseHL(dexes, metas)[1].coin, "xyz:AAPL");
  for (const value of [metas.slice(1), [metas[0], { universe: [] }],
    [metas[0], { collateralToken: 0, universe: [{ name: "AAPL", maxLeverage: 20 }] }],
    [metas[0], { collateralToken: 0, universe: [{ name: "xyz:AAPL", maxLeverage: 20, isDelisted: "false" }] }],
    [{ collateralToken: 0, universe: [] }, metas[1]],
    [metas[0], { collateralToken: 0, universe: [{ name: "xyz:AAPL", maxLeverage: 20 }, { name: "xyz:AAPL", maxLeverage: 20 }] }]]) assert.throws(() => parseHL(dexes, value));
  for (const value of [[], [{ name: "xyz" }], [null, { name: "xyz" }, { name: "xyz" }]]) assert.throws(() => dexNames(value));
});
Deno.test("markets HL always wins including other builders; xStocks is never consulted", async () => {
  const sources = catalogs([market("vntl:AAPL"), market("xyz:AAPL")]);
  sources.xstocks = () => { throw Error("must not read issuer"); };
  const route = await resolveRoute("AAPL", sources, now);
  assert.equal(route.venue, "hyperliquid"); assert.equal(route.reason, "hl_listed");
  assert.ok(route.market && "coin" in route.market); assert.equal(route.market.coin, "xyz:AAPL");
  assert.equal(route.executionEnabled, false);
  sources.hl = async () => ({ at, values: [market("vntl:AAPL")] });
  assert.equal((await resolveRoute("AAPL", sources, now)).venue, "hyperliquid");
});
Deno.test("markets collateral incompatibility, delisting and provider failures have distinct routes", async () => {
  let sources = catalogs([market("xyz:AEHR", 7)]);
  sources.xstocks = () => { throw Error("must not fall back"); };
  assert.equal((await resolveRoute("AEHR", sources, now)).status, "blocked");
  sources = catalogs([market("xyz:AEHR", 0, true)]);
  assert.equal((await resolveRoute("AEHR", sources, now)).venue, "xstocks");
  sources.hl = () => { throw Error("timeout including secret upstream payload"); };
  await assert.rejects(() => resolveRoute("AEHR", sources, now));
});
Deno.test("markets refuse expired/future HL evidence and recheck after a slow issuer lookup", async () => {
  const sources = catalogs([]);
  for (const time of [at - 30_000, at + 1]) {
    sources.hl = async () => ({ at: time, values: [] });
    await assert.rejects(() => resolveRoute("AEHR", sources, now));
  }
  sources.hl = async () => ({ at, values: [] });
  sources.xstocks = async () => ({ at, values: parseXStocks([rawStock()]) });
  let time = at;
  sources.xstocks = async () => { time += 30_000; return { at: time, values: parseXStocks([rawStock()]) }; };
  await assert.rejects(() => resolveRoute("AEHR", sources, () => time));
  time = at;
  sources.xstock = async () => ({ at: time, values: parseXStocks([rawStock()]) });
  let hlCalls = 0;
  sources.hl = async () => ({ at: time, values: hlCalls++ ? [market("xyz:AEHR")] : [] });
  assert.equal((await resolveRoute("AEHR", sources, () => time)).venue, "hyperliquid");
  assert.equal(hlCalls, 2);
});
Deno.test("markets issuer identity is exact, unique and uses validated 32-byte Solana mints", async () => {
  assert.equal(parseXStocks([rawStock()])[0].mint, mint);
  const invalid = [
    { ...rawStock(), deployments: [{ network: "Solana", address: "bad" }] },
    { ...rawStock(), deployments: [{ network: "Solana", address: USDC_MINT }] },
    { ...rawStock(), deployments: [{ network: "Solana", address: mint }, { network: "Solana", address: mint }] },
    { ...rawStock(), isTradingHalted: "false" },
    { ...rawStock(), underlying: { symbol: "bad/ticker", currency: "USD" } },
  ];
  for (const value of invalid) assert.throws(() => parseXStocks([value]));
  assert.throws(() => parseXStocks([rawStock(), rawStock()]));
  assert.throws(() => parseXStocks([rawStock(), { ...rawStock(), id: "22345678-1234-1234-1234-123456789abc" }]));
  const sources = catalogs([]);
  let route = await resolveRoute("AEHR", sources, now);
  assert.equal(route.product, "spot"); assert.ok(route.market && "mint" in route.market); assert.equal(route.market.maxLeverage, 1);
  sources.xstocks = async () => ({ at, values: parseXStocks([{ ...rawStock(), trading: { isTradingHalted: true } }]) });
  sources.xstock = sources.xstocks;
  assert.equal((await resolveRoute("AEHR", sources, now)).reason, "xstocks_halted");
  sources.xstocks = async () => ({ at, values: parseXStocks([{ ...rawStock(), deployments: [] }]) });
  assert.equal((await resolveRoute("AEHR", sources, now)).status, "unsupported");
  route = await resolveRoute("OUST", sources, now); assert.equal(route.venue, "none");
});
Deno.test("markets cache coalesces complete snapshots and never resurrects stale results", async () => {
  let time = at, calls = 0, fail = false;
  const cache = catalogCache(async () => { calls++; if (fail) throw Error("failure"); return [1]; }, () => time);
  const a = cache(), b = cache(); assert.equal(a, b); assert.deepEqual((await a).values, [1]);
  await cache(); assert.equal(calls, 1);
  time += 30_000; fail = true; await assert.rejects(cache); assert.equal(calls, 2);
  await assert.rejects(cache); assert.equal(calls, 3);
  fail = false; assert.equal((await cache()).at, time);
  const slow = catalogCache(async () => { time += 30_000; return []; }, () => time);
  await assert.rejects(slow);
});
Deno.test("markets live asset detail cannot change identity or hide a halt", async () => {
  const sources = catalogs([]);
  sources.xstock = async () => ({ at, values: parseXStocks([{ ...rawStock(), isTradingHalted: true }]) });
  assert.equal((await resolveRoute("AEHR", sources, now)).status, "blocked");
  for (const patch of [{ symbol: "OTHERx" }, { id: "22345678-1234-1234-1234-123456789abc" },
    { underlying: { symbol: "OTHER", currency: "USD" } }, { deployments: [] }]) {
    sources.xstock = async () => ({ at, values: parseXStocks([{ ...rawStock(), ...patch }]) });
    await assert.rejects(() => resolveRoute("AEHR", sources, now));
  }
  sources.xstock = async () => ({ at: at - 30_000, values: parseXStocks([rawStock()]) });
  await assert.rejects(() => resolveRoute("AEHR", sources, now));
  sources.xstock = () => { throw Error("issuer unavailable"); };
  await assert.rejects(() => resolveRoute("AEHR", sources, now));
});
Deno.test("markets identity registry has a separate bounded TTL; it cannot authorize stale status", async () => {
  const sources = catalogs([]);
  sources.xstocks = async () => ({ at: at - 599_999, values: parseXStocks([rawStock()]) });
  const result = await resolveRoute("AEHR", sources, now);
  assert.equal(result.status, "available"); assert.equal(result.observedAt, new Date(at).toISOString());
  sources.xstocks = async () => ({ at: at - 600_000, values: parseXStocks([rawStock()]) });
  await assert.rejects(() => resolveRoute("AEHR", sources, now));
});
Deno.test("markets fixture responses preserve read-only discovery contract", async () => {
  const fixture = JSON.parse(await Deno.readTextFile(new URL("../../../contracts/fixtures/equity-routing.json", import.meta.url)));
  const sources = catalogs();
  const actual = [];
  for (const ticker of ["AAPL", "AEHR", "UNKNOWN"]) actual.push(await resolveRoute(ticker, sources, now));
  assert.equal(fixture.fixtureOnly, true); assert.deepEqual(actual, fixture.routes);
});
Deno.test("markets providers verify stable HL registry ordering before accepting metadata", async () => {
  const types: string[] = [];
  const fetcher: typeof fetch = (_url, init) => {
    const type = JSON.parse(String(init?.body)).type; types.push(type);
    if (type === "allPerpMetas") return fetchJSON([{ collateralToken: 0, universe: [{ name: "BTC", maxLeverage: 40 }] }]);
    return fetchJSON(types.length === 1 ? [null] : [null, { name: "xyz" }]);
  };
  await assert.rejects(() => providers(fetcher, now).hl());
  assert.deepEqual(types, ["perpDexs", "allPerpMetas", "perpDexs"]);
});
Deno.test("markets issuer traverses all pages and rejects incomplete or cyclic pagination", async () => {
  const pages: string[] = [];
  const fetcher: typeof fetch = (input) => {
    const url = new URL(String(input)); pages.push(url.searchParams.get("page")!);
    assert.equal(url.hostname, "api.xstocks.fi"); assert.equal(url.searchParams.get("network"), "Solana");
    const p = Number(url.searchParams.get("page"));
    return fetchJSON({ nodes: p === 0 ? [{ ...rawStock(), id: "22345678-1234-1234-1234-123456789abc", underlying: { symbol: "OTHER", currency: "EUR" } }] : [rawStock()],
      page: { currentPage: p, hasNextPage: p === 0 } });
  };
  assert.equal((await providers(fetcher, now).xstocks()).values[0].ticker, "AEHR");
  assert.deepEqual(pages, ["0", "1"]);
  for (const payload of [{ nodes: [], page: { currentPage: 0, hasNextPage: true } },
    { nodes: [], page: { currentPage: 1, hasNextPage: false } }, { nodes: [], page: {} }]) {
    await assert.rejects(() => providers(() => fetchJSON(payload), now).xstocks());
  }
  let calls = 0;
  await assert.rejects(() => providers(() => fetchJSON({ nodes: [rawStock()], page: { currentPage: calls++, hasNextPage: true } }), now).xstocks());
  assert.equal(calls, 100);
});
Deno.test("markets quote is wallet-free, exact-pair, exact-input and never executable", async () => {
  const route = await resolveRoute("AEHR", catalogs([]), now);
  const quote = { inputMint: USDC_MINT, outputMint: mint, inAmount: "1000000", outAmount: "20000", router: "metis", transaction: null, requestId: "private-provider-id" };
  let calls = 0;
  const fetcher: typeof fetch = (input, init) => {
    calls++;
    const url = new URL(String(input));
    assert.equal(url.origin + url.pathname, "https://api.jup.ag/swap/v2/order");
    assert.deepEqual([...url.searchParams.keys()].sort(), ["amount", "inputMint", "outputMint"]);
    assert.equal(new Headers(init?.headers).get("x-api-key"), "test-key"); assert.equal(init?.redirect, "error");
    return fetchJSON(quote);
  };
  const result = await preview(route, "1000000", "test-key", fetcher, now);
  assert.equal(result.executable, false); assert.equal(result.gasCoverage, "unverified");
  assert.equal(result.outputAmountRaw, "20000"); assert.equal(calls, 1);
  assert.ok(!("transaction" in result) && !("requestId" in result));
  for (const patch of [{ inputMint: mint }, { outputMint: USDC_MINT }, { inAmount: "1" }, { outAmount: "0" },
    { router: "new-router" }, { transaction: "unsigned-bytes" }, { errorCode: 3 }, { errorMessage: "secret" }]) {
    await assert.rejects(() => preview(route, "1000000", "test-key", () => fetchJSON({ ...quote, ...patch }), now), (error: Error) => error.message === "quote_unavailable");
  }
  await assert.rejects(() => preview(awaitRouteHL(), "1000000", "test-key", fetcher, now));
  function awaitRouteHL() { return { ...route, venue: "hyperliquid" as const }; }
});
Deno.test("markets HTTP reader bounds response bytes and requires JSON even without Content-Length", async () => {
  await assert.rejects(() => readJSON("https://test.invalid", {}, () => Promise.resolve(new Response("x".repeat(2_097_153), { headers: { "Content-Type": "application/json" } }))));
  await assert.rejects(() => readJSON("https://test.invalid", {}, () => Promise.resolve(new Response("{}", { headers: { "Content-Type": "text/html" } }))));
});
Deno.test("markets authenticate before providers and reject anonymous/untrusted identities", async () => {
  let calls = 0;
  const sources: Catalogs = { hl: () => { calls++; throw Error("provider"); }, xstocks: () => { calls++; throw Error("provider"); },
    xstock: () => { calls++; throw Error("provider"); } };
  const options = { catalogs: sources, previewsEnabled: false, now };
  for (const [req, authClient] of [[request("route?ticker=AEHR", "GET", ""), client()],
    [request("route?ticker=AEHR"), client(true)], [request("route?ticker=AEHR"), client(false, "email")]] as const) {
    assert.equal((await handleMarkets(req, authClient, options)).status, 401);
  }
  assert.equal(calls, 0);
});
Deno.test("markets API default is closed, sanitized, no-store and has no mutation endpoints", async () => {
  const options = { catalogs: catalogs([]), previewsEnabled: false, now };
  let response = await handleMarkets(request("route?ticker=AEHR"), client(), options);
  assert.equal(response.status, 200); assert.equal(response.headers.get("cache-control"), "no-store");
  for (const path of ["route?ticker=AEHR&ticker=AAPL", "route?ticker=AEHR&mint=fake", "preview?ticker=AEHR&amountUSDC=0", "route?ticker=%20AEHR"]) {
    assert.equal((await handleMarkets(request(path), client(), options)).status, 422);
  }
  response = await handleMarkets(request("preview?ticker=AEHR&amountUSDC=1"), client(), options);
  assert.equal(response.status, 503); assert.equal((await response.json()).error, "preview_disabled");
  for (const path of ["submit", "execute", "sign", "route?ticker=AEHR"]) assert.equal((await handleMarkets(request(path, "POST"), client(), options)).status, 404);
  options.catalogs.hl = () => { throw Error("api-key-secret-upstream-body"); };
  response = await handleMarkets(request("route?ticker=AEHR"), client(), options);
  assert.equal(response.status, 503); assert.deepEqual(await response.json(), { error: "markets_unavailable" });
});
Deno.test("markets preview does not switch listed HL assets to xStocks or bypass disabled credentials", async () => {
  const options = { catalogs: catalogs(), previewsEnabled: true, apiKey: "test-key", now };
  const result = await handleMarkets(request("preview?ticker=AAPL&amountUSDC=1"), client(), options);
  assert.equal(result.status, 409); assert.equal((await result.json()).error, "xstocks_route_required");
  const missing = await handleMarkets(request("preview?ticker=AEHR&amountUSDC=1"), client(), { ...options, apiKey: undefined });
  assert.equal(missing.status, 503);
});
