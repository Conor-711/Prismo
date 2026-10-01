import { handleFeed } from "../supabase/functions/bsmart-feed/handler.ts";
import { parsePublicPortfolio } from "../supabase/functions/bsmart-feed/public_portfolio.ts";

function assert(value: unknown, message = "assertion failed"): asserts value { if (!value) throw Error(message); }
const publicID = "11111111-1111-4111-8111-111111111111";
const wallet = "0x" + "ab".repeat(20);
const dexs = [null, { name: "xyz" }];
const empty = { assetPositions: [] };
const state = { assetPositions: [{ type: "oneWay", position: { coin: "xyz:NVDA", szi: "-2",
  positionValue: "240", unrealizedPnl: "-12", returnOnEquity: "-0.05",
  entryPx: "126", leverage: { value: 5 } } }] };
const spot = { balances: [{ coin: "USDC", token: 0, total: "7.25" }] };
const portfolio = [["perpDay", { accountValueHistory: [[1000, "30"], [2000, "35"]] }],
  ["perpWeek", { accountValueHistory: [[1000, "25"], [2000, "35"]] }]];

Deno.test("public portfolio combines separate spot and perps without double-counting shared collateral", () => {
  const result = parsePublicPortfolio(dexs, [empty, state], spot, portfolio, "disabled");
  assert(result.perpsEquityUSD === "35" && result.spotUSDC === "7.25");
  assert(result.accountValueUSD === "42.25" && result.dayChangeUSD === "5");
  assert(result.positions.length === 1 && result.positions[0].side === "short");
  assert(result.history.day.length === 2 && result.history.week.length === 2);
  const shared = parsePublicPortfolio(dexs, [empty, state], spot, portfolio, "unifiedAccount");
  assert(shared.accountValueUSD === "7.25" && shared.dayChangeUSD === null);
  const unknown = parsePublicPortfolio(dexs, [empty, state], spot, portfolio, null);
  assert(unknown.accountValueUSD === null && unknown.positions.length === 1);
});

Deno.test("current equity keeps a spot-only account visible before portfolio history exists", () => {
  const main = { assetPositions: [], marginSummary: { accountValue: "0" } };
  const secondary = { assetPositions: [], marginSummary: { accountValue: "0" } };
  const result = parsePublicPortfolio(dexs, [main, secondary], spot, [], "disabled");
  assert(result.perpsEquityUSD === "0" && result.accountValueUSD === "7.25");
  assert(result.dayChangeUSD === null && result.history.day.length === 0);
});

Deno.test("current clearinghouse equity takes precedence over a stale history point", () => {
  const main = { assetPositions: [], marginSummary: { accountValue: "33" } };
  const secondary = { assetPositions: [], marginSummary: { accountValue: "2" } };
  const result = parsePublicPortfolio(dexs, [main, secondary], spot, [], "disabled");
  assert(result.perpsEquityUSD === "35" && result.accountValueUSD === "42.25");
});

Deno.test("portfolio rejects malformed exchange values and incomplete dex state", () => {
  for (const states of [[empty], [empty, { assetPositions: [{ ...state.assetPositions[0],
    position: { ...state.assetPositions[0].position, positionValue: "NaN" } }] }],
    [empty, { assetPositions: [state.assetPositions[0], state.assetPositions[0]] }]]) {
    let rejected = false;
    try { parsePublicPortfolio(dexs, states, spot, portfolio, "disabled"); } catch { rejected = true; }
    assert(rejected);
  }
});

Deno.test("profile portfolio reads only the server-bound wallet and requires authentication", async () => {
  const calls: Record<string, unknown>[] = [];
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: "viewer", identities: [{ provider: "google" }] } } }) },
    from: (table: string) => {
      const query: any = { select: () => query, eq: () => query,
        maybeSingle: async () => ({ data: table === "bsmart_wallets" ? { address: wallet } : { account_id: "owner" } }) };
      return query;
    },
  };
  const deps = { markets: {}, catalog: async () => ({}), info: async (body: Record<string, unknown>) => {
    calls.push(body);
    if (body.type === "perpDexs") return dexs;
    if (body.type === "clearinghouseState") return body.dex === "xyz" ? state : empty;
    if (body.type === "spotClearinghouseState") return spot;
    if (body.type === "userAbstraction") return "disabled";
    return portfolio;
  } };
  const url = `https://test.invalid/bsmart-feed/profiles/${publicID}/portfolio`;
  assert((await handleFeed(new Request(url), client, deps)).status === 401);
  assert(calls.length === 0);
  const response = await handleFeed(new Request(url + "?wallet=0xdead", {
    headers: { Authorization: "Bearer a.b.c" },
  }), client, deps);
  const result = await response.json();
  assert(response.status === 200 && result.positions[0].coin === "xyz:NVDA");
  assert(calls.every(call => !Object.hasOwn(call, "user") || call.user === wallet));
  assert(!("wallet" in result) && !("account_id" in result));
});

Deno.test("own portfolio uses the authenticated account even when its profile is hidden", async () => {
  const accountID = "22222222-2222-4222-8222-222222222222";
  const filters: { table: string; column: string; value: unknown }[] = [];
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: accountID, identities: [{ provider: "google" }] } } }) },
    from: (table: string) => {
      const query: any = {
        select: () => query,
        eq: (column: string, value: unknown) => { filters.push({ table, column, value }); return query; },
        maybeSingle: async () => ({ data: { address: wallet } }),
      };
      return query;
    },
  };
  const calls: Record<string, unknown>[] = [];
  const deps = { markets: {}, catalog: async () => ({}), info: async (body: Record<string, unknown>) => {
    calls.push(body);
    if (body.type === "perpDexs") return dexs;
    if (body.type === "clearinghouseState") return body.dex === "xyz" ? state : empty;
    if (body.type === "spotClearinghouseState") return spot;
    if (body.type === "userAbstraction") return "disabled";
    return portfolio;
  } };
  const url = "https://test.invalid/bsmart-feed/profiles/me/portfolio?wallet=0xdead";
  assert((await handleFeed(new Request(url), client, deps)).status === 401);
  assert(filters.length === 0 && calls.length === 0);
  const response = await handleFeed(new Request(url, { headers: { Authorization: "Bearer a.b.c" } }), client, deps);
  const result = await response.json();
  assert(response.status === 200 && result.positions[0].coin === "xyz:NVDA");
  const walletFilters = filters.filter(({ table, column, value }) =>
    table === "bsmart_wallets" && column === "account_id" && value === accountID);
  assert(filters.slice().length === 1 && walletFilters.length === 1);
  assert(calls.every(call => !Object.hasOwn(call, "user") || call.user === wallet));
});

Deno.test("portfolio remains available when account mode cannot be checked", async () => {
  const client: any = {
    from: () => {
      const query: any = { select: () => query, eq: () => query,
        maybeSingle: async () => ({ data: { address: wallet } }) };
      return query;
    },
  };
  const info = async (body: Record<string, unknown>) => {
    if (body.type === "perpDexs") return dexs;
    if (body.type === "clearinghouseState") return body.dex === "xyz" ? state : empty;
    if (body.type === "spotClearinghouseState") return spot;
    if (body.type === "userAbstraction") throw new Error("unavailable");
    return portfolio;
  };
  const { accountPortfolio } = await import("../supabase/functions/bsmart-feed/public_portfolio.ts");
  const result = await accountPortfolio(client, info, "owner");
  assert(result.status === "ready" && result.accountValueUSD === null && result.positions.length === 1);
});

Deno.test("missing wallet and exchange outage are distinct from an empty account", async () => {
  let linked = false;
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: "viewer", identities: [{ provider: "apple" }] } } }) },
    from: (table: string) => {
      const query: any = { select: () => query, eq: () => query,
        maybeSingle: async () => ({ data: table === "bsmart_wallets"
          ? (linked ? { address: wallet } : null) : { account_id: "owner" } }) };
      return query;
    },
  };
  const deps = { markets: {}, catalog: async () => ({}), info: async () => { throw Error("exchange offline"); } };
  const request = new Request(`https://test.invalid/bsmart-feed/profiles/${publicID}/portfolio`,
    { headers: { Authorization: "Bearer a.b.c" } });
  const missing = await handleFeed(request, client, deps);
  assert(missing.status === 200 && (await missing.json()).status === "not_connected");
  linked = true;
  const unavailable = await handleFeed(request, client, deps);
  assert(unavailable.status === 503 && (await unavailable.json()).error === "feed_unavailable");
});

Deno.test("history outage does not hide verified live account value", async () => {
  const client: any = {
    from: () => {
      const query: any = { select: () => query, eq: () => query,
        maybeSingle: async () => ({ data: { address: wallet } }) };
      return query;
    },
  };
  const info = async (body: Record<string, unknown>) => {
    if (body.type === "perpDexs") return dexs;
    if (body.type === "clearinghouseState") return { assetPositions: [], marginSummary: { accountValue: "0" } };
    if (body.type === "spotClearinghouseState") return spot;
    if (body.type === "userAbstraction") return "disabled";
    throw new Error("history_unavailable");
  };
  const { accountPortfolio } = await import("../supabase/functions/bsmart-feed/public_portfolio.ts");
  const result = await accountPortfolio(client, info, "owner");
  assert(result.accountValueUSD === "7.25" && result.history.day.length === 0 && result.dayChangeUSD === null);
});
