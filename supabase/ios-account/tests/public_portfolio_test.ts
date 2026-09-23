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

Deno.test("public portfolio preserves real on-chain positions and does not add shared cash to equity", () => {
  const result = parsePublicPortfolio(dexs, [empty, state], spot, portfolio);
  assert(result.perpsEquityUSD === "35" && result.spotUSDC === "7.25");
  assert(result.positions.length === 1 && result.positions[0].side === "short");
  assert(result.history.day.length === 2 && result.history.week.length === 2);
  assert(!("totalAssetsUSD" in result));
});

Deno.test("portfolio rejects malformed exchange values and incomplete dex state", () => {
  for (const states of [[empty], [empty, { assetPositions: [{ ...state.assetPositions[0],
    position: { ...state.assetPositions[0].position, positionValue: "NaN" } }] }],
    [empty, { assetPositions: [state.assetPositions[0], state.assetPositions[0]] }]]) {
    let rejected = false;
    try { parsePublicPortfolio(dexs, states, spot, portfolio); } catch { rejected = true; }
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
