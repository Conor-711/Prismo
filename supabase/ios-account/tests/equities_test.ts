import { strict as assert } from "node:assert";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { Asset, NETWORKS, parseAsset, parseIssuerRegistry } from "../supabase/functions/bsmart-equities/assets.ts";
import { V1_TICKERS } from "../supabase/functions/bsmart-equities/inventory.ts";
import { EVMCatalogs, resolveEVMRoute } from "../supabase/functions/bsmart-equities/routing.ts";
import { equityProviders } from "../supabase/functions/bsmart-equities/providers.ts";
import { handleEquities } from "../supabase/functions/bsmart-equities/handler.ts";

const at = Date.parse("2026-10-01T00:00:00Z"), now = () => at;
const token = "0x1111111111111111111111111111111111111111";
function raw(ticker = "ASTS") {
  return { id: "12345678-1234-1234-1234-123456789abc", symbol: ticker + "x", name: ticker,
    underlying: { symbol: ticker, currency: "USD" }, isTradingHalted: false,
    trading: { isTradingHalted: false, tradingHoursMode: "TwentyFourFive" }, deployments: [{ network: "Ethereum", address: token,
      stablecoins: [{ network: "Ethereum", symbol: "USDC", address: NETWORKS.Ethereum.usdc, decimals: 6 }] }] };
}
const stock = () => parseAsset(raw(), "ASTS");
const market = (coin = "xyz:ASTS", collateralToken = 0, delisted = false) => ({ coin, dex: coin.split(":")[0], collateralToken, maxLeverage: 10, delisted });
function sources(): EVMCatalogs {
  return { hl: async () => ({ at, values: [] }), registry: async () => ({ at, values: [stock()] }), asset: async () => ({ at, values: [stock()] }) };
}
function client(anonymous = false, provider = "apple", error: unknown = null) {
  return { auth: { getUser: async () => ({ data: { user: { id: crypto.randomUUID(), is_anonymous: anonymous,
    identities: [{ provider }] } }, error }) } } as unknown as SupabaseClient;
}
const request = (path = "route?ticker=ASTS", method = "GET", auth = "Bearer a.b.c") =>
  new Request("https://test.invalid/bsmart-equities/" + path, { method, headers: { authorization: auth } });

Deno.test("equities inventory has 50 distinct discovery targets, never a global execution approval", async () => {
  assert.equal(V1_TICKERS.size, 50);
  for (const ticker of ["SPY", "QQQ", "ASTS", "JPM", "WMT"]) assert.ok(V1_TICKERS.has(ticker));
  assert.equal(V1_TICKERS.has("NVDA"), false);
  const s = sources();
  s.registry = () => { throw Error("outside inventory must not read issuer"); };
  assert.equal((await resolveEVMRoute("OUST", s, now)).reason, "not_in_v1");
});
Deno.test("equities full issuer registry rejects ambiguous IDs, underlying and deployed tokens", () => {
  assert.equal(parseIssuerRegistry([raw()])[0].ticker, "ASTS");
  assert.throws(() => parseIssuerRegistry([raw(), raw()]));
  const duplicateUnderlying = { ...raw(), id: "22345678-1234-1234-1234-123456789abc" };
  assert.throws(() => parseIssuerRegistry([raw(), duplicateUnderlying]));
  const duplicateToken = { ...raw("SPY"), id: duplicateUnderlying.id };
  assert.throws(() => parseIssuerRegistry([raw(), duplicateToken]));
  assert.equal(parseIssuerRegistry([{ ...raw(), underlying: { symbol: "ASTS", currency: "EUR" } }]).length, 0);
});
Deno.test("equities HL dominates all discovery inventory and unsupported collateral blocks fallback", async () => {
  const s = sources();
  s.registry = () => { throw Error("never consult issuer for HL"); };
  s.hl = async () => ({ at, values: [market("vntl:ASTS"), market()] });
  let r = await resolveEVMRoute("ASTS", s, now);
  assert.equal(r.venue, "hyperliquid"); assert.equal(r.market?.coin, "xyz:ASTS"); assert.deepEqual(r.instruments, []);
  s.hl = async () => ({ at, values: [market("xyz:ASTS", 7)] });
  r = await resolveEVMRoute("ASTS", s, now);
  assert.equal(r.status, "blocked"); assert.equal(r.reason, "hl_collateral_unsupported");
  s.hl = async () => ({ at, values: [market("xyz:NVDA")] });
  assert.equal((await resolveEVMRoute("NVDA", s, now)).venue, "hyperliquid");
});
Deno.test("equities resolve exact raw instruments but never infer execution, gas or weekend closure", async () => {
  const r = await resolveEVMRoute("asts", sources(), now);
  assert.equal(r.product, "spot"); assert.equal(r.status, "available"); assert.equal(r.executionEnabled, false);
  assert.equal(r.gasCoverage, "unverified"); assert.equal(r.defaultSaleProceedsDestination, "hyperliquid_perps");
  assert.equal(r.market, null); assert.deepEqual(r.instruments, [{ assetId: raw().id, symbol: "ASTSx", network: "Ethereum",
    chainId: 1, token, usdc: NETWORKS.Ethereum.usdc, tokenVariant: "raw", maxLeverage: 1 }]);
});
Deno.test("equities live halts and delisted HL markets have independent effects", async () => {
  const s = sources();
  s.hl = async () => ({ at, values: [market("xyz:ASTS", 0, true)] });
  s.asset = async () => ({ at, values: [{ ...stock(), halted: true }] });
  assert.equal((await resolveEVMRoute("ASTS", s, now)).reason, "xstocks_halted");
  s.registry = async () => ({ at, values: [] });
  assert.equal((await resolveEVMRoute("ASTS", s, now)).reason, "not_listed");
});
Deno.test("equities metadata drift, expired detail and stale/future full catalogs fail closed", async () => {
  const s = sources();
  for (const time of [at - 30_000, at + 1]) {
    s.hl = async () => ({ at: time, values: [] });
    await assert.rejects(() => resolveEVMRoute("ASTS", s, now));
  }
  s.hl = async () => ({ at, values: [] });
  for (const patch of [{ id: "other" }, { symbol: "OTHERx" }, { ticker: "OTHER" }, { deployments: [] }]) {
    s.asset = async () => ({ at, values: [{ ...stock(), ...patch } as Asset] });
    await assert.rejects(() => resolveEVMRoute("ASTS", s, now));
  }
  s.asset = async () => ({ at: at - 30_000, values: [stock()] });
  await assert.rejects(() => resolveEVMRoute("ASTS", s, now));
  s.registry = async () => ({ at: at - 600_000, values: [stock()] });
  await assert.rejects(() => resolveEVMRoute("ASTS", s, now));
});
Deno.test("equities recheck HL after cold discovery rather than authorize a new-listing fallback", async () => {
  const s = sources(); let time = at, calls = 0;
  s.hl = async () => ({ at: time, values: calls++ ? [market()] : [] });
  s.registry = async () => { time += 30_000; return { at: time, values: [stock()] }; };
  s.asset = async () => ({ at: time, values: [stock()] });
  assert.equal((await resolveEVMRoute("ASTS", s, () => time)).venue, "hyperliquid");
  assert.equal(calls, 2);
});
Deno.test("equities retain registry TTL checks after a slow HL refresh", async () => {
  const s = sources(); let time = at, calls = 0;
  s.hl = async () => { if (calls++) time += 20_000; return { at: time, values: [] }; };
  s.registry = async () => ({ at: at - 550_000, values: [stock()] });
  s.asset = async () => { time += 30_000; return { at: time, values: [stock()] }; };
  await assert.rejects(() => resolveEVMRoute("ASTS", s, () => time));
  assert.equal(calls, 2);
});
Deno.test("equities provider consumes complete unfiltered pages before parsing", async () => {
  const pages: number[] = [];
  const fetcher: typeof fetch = input => {
    const u = new URL(String(input));
    assert.equal(u.hostname, "api.xstocks.fi"); assert.equal(u.searchParams.has("network"), false);
    assert.equal(u.searchParams.get("pageSize"), "50");
    const page = Number(u.searchParams.get("page")); pages.push(page);
    return Promise.resolve(Response.json({ nodes: page ? [raw()] : [{ ...raw("EUR"),
      id: "22345678-1234-1234-1234-123456789abc", underlying: { symbol: "EUR", currency: "EUR" } }],
      page: { currentPage: page, hasNextPage: !page } }));
  };
  const p = equityProviders(fetcher, now);
  assert.equal((await p.registry()).values[0].ticker, "ASTS");
  await p.registry(); assert.deepEqual(pages, [0, 1]);
  for (const value of [{ nodes: [], page: { currentPage: 0, hasNextPage: true } },
    { nodes: [raw()], page: { currentPage: 1, hasNextPage: false } }]) {
    await assert.rejects(() => equityProviders(() => Promise.resolve(Response.json(value)), now).registry());
  }
});
Deno.test("equities registry deadline never caches an over-budget final page", async () => {
  let time = at;
  const p = equityProviders(() => { time += 90_000; return Promise.resolve(Response.json({ nodes: [raw()], page: { currentPage: 0, hasNextPage: false } })); }, () => time);
  await assert.rejects(p.registry);
  await assert.rejects(p.registry);
});
Deno.test("equities retry only failed metadata GETs with a bounded attempt count", async () => {
  let attempts = 0;
  const p = equityProviders(() => {
    if (++attempts === 1) return Promise.reject(Error("timeout"));
    return Promise.resolve(Response.json({ nodes: [raw()], page: { currentPage: 0, hasNextPage: false } }));
  }, now);
  assert.equal((await p.registry()).values.length, 1); assert.equal(attempts, 2);
  attempts = 0;
  const failed = equityProviders(() => { attempts++; return Promise.reject(Error("secret provider body")); }, now);
  await assert.rejects(failed.registry, /issuer_registry_unavailable/);
  assert.equal(attempts, 2);
});
Deno.test("equities authentication and kill switch run before any upstream requests", async () => {
  const s = sources(); s.hl = () => { throw Error("must not request provider"); };
  const options = { catalogs: s, discoveryEnabled: true, now };
  for (const c of [client(true), client(false, "email"), client(false, "apple", Error("secret"))]) {
    assert.equal((await handleEquities(request(), c, options)).status, 401);
  }
  assert.equal((await handleEquities(request("route?ticker=ASTS", "GET", "Bearer invalid"), client(), options)).status, 401);
  const disabled = await handleEquities(request(), client(), { ...options, discoveryEnabled: false });
  assert.equal(disabled.status, 503); assert.deepEqual(await disabled.json(), { error: "discovery_disabled" });
});
Deno.test("equities reject arbitrary inputs, mutations and leak-free provider errors", async () => {
  const options = { catalogs: sources(), discoveryEnabled: true, now };
  for (const path of ["route?ticker=ASTS&ticker=SPY", "route?ticker=ASTS&network=Ink", "route?ticker=xyz%3AASTS", "route"]) {
    assert.equal((await handleEquities(request(path), client(), options)).status, 422);
  }
  assert.equal((await handleEquities(request("route?ticker=ASTS", "POST"), client(), options)).status, 404);
  assert.equal((await handleEquities(request("submit?ticker=ASTS"), client(), options)).status, 404);
  options.catalogs.hl = () => { throw Error("upstream token=SECRET"); };
  const failed = await handleEquities(request(), client(), options);
  assert.equal(failed.status, 503); assert.equal(failed.headers.get("cache-control"), "no-store");
  assert.deepEqual(await failed.json(), { error: "equities_unavailable" });
});
Deno.test("equities provider resolves official symbols and does not construct token addresses", async () => {
  const p = equityProviders(input => {
    assert.equal(String(input), "https://api.xstocks.fi/api/v2/public/assets/ASTSx");
    return Promise.resolve(Response.json(raw()));
  }, now);
  assert.equal((await p.asset("ASTSx")).values[0].deployments[0].token, token);
});
Deno.test("equities fixtures preserve the stable read-only wire contract", async () => {
  const fixture = JSON.parse(await Deno.readTextFile(new URL("../../../contracts/fixtures/evm-equity-routing.json", import.meta.url)));
  const s = sources(), routes = [await resolveEVMRoute("ASTS", s, now)];
  s.hl = async () => ({ at, values: [market()] });
  routes.push(await resolveEVMRoute("ASTS", s, now), await resolveEVMRoute("OUST", s, now));
  assert.equal(fixture.fixtureOnly, true); assert.deepEqual(routes, fixture.routes);
});
