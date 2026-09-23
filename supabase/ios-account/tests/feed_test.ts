import { type Intent, type RegisteredOrder, decimal, validateIntent, verifyExecution, verifyHip3Market } from "../supabase/functions/bsmart-feed/verification.ts";
import { handleFeed, sharingInput } from "../supabase/functions/bsmart-feed/handler.ts";

function assert(value: unknown, message = "assertion failed"): asserts value { if (!value) throw new Error(message); }
async function rejects(action: () => unknown) {
  let rejected = false; try { await action(); } catch { rejected = true; } assert(rejected, "expected rejection");
}
const now = 1800000000000;
const intent: Intent = { opinionId: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb", authorId: "x:investor", ticker: "NVDA",
  cloid: "0x11111111111111111111111111111111", coin: "xyz:NVDA", side: "buy", size: "2", limitPrice: "120",
  nonce: now - 5000, expiresAfter: now + 55000 };
const record: RegisteredOrder = { id: crypto.randomUUID(), wallet: "0x" + "22".repeat(20), intent,
  registered_at: new Date(now - 4000).toISOString() };
const status = () => ({ status: "order", order: { status: "filled", statusTimestamp: now - 1000,
  order: { cloid: intent.cloid, coin: intent.coin, side: "B", origSz: "2", sz: "0", limitPx: "120",
    reduceOnly: false, isTrigger: false, tif: "Ioc", oid: 42, timestamp: now - 3000 } } });
const fills = () => [1, 2].map((tid, index) => ({ tid, oid: 42, coin: intent.coin, side: "B", px: "110.1",
  sz: "1", time: now - 2000 + index * 100, hash: "0x" + "ab".repeat(32) }));
const info = (s = status(), f = fills()) => async (body: Record<string, unknown>) => body.type === "orderStatus" ? s : f;

Deno.test("exact fill values and one order event aggregate partial fills", async () => {
  const result = await verifyExecution(record, info(), now);
  assert(result?.notionalUSD === "220.2"); assert(result.fillIDs.length === 2);
  assert(result.executedAt === new Date(now - 2000).toISOString());
  assert(JSON.stringify(await verifyExecution(record, info(), now)) === JSON.stringify(result));
});
Deno.test("registration validates market mapping and rejects untrusted fields", async () => {
  assert(validateIntent(intent, now).coin === intent.coin);
  for (const patch of [{ coin: "spot:NVDA", ticker: "NVDA?" }, { accountId: "attacker" },
    { nonce: now - 60000 }, { expiresAfter: now - 1 }, { side: "long" }, { size: "NaN" },
    { cloid: "0x" + "00".repeat(16) }, { opinionId: "not-a-uuid" }]) {
    await rejects(() => validateIntent({ ...intent, ...patch }, now));
  }
});
Deno.test("old and newly listed HIP-3 markets resolve from live exchange metadata", async () => {
  const dexs = [null, { name: "xyz" }, { name: "para" }, { name: "newdex" }];
  const metadata: Record<string, any> = {
    xyz: { collateralToken: 0, universe: [{ name: "xyz:NVDA", maxLeverage: 20, szDecimals: 2 }] },
    para: { collateralToken: 0, universe: [{ name: "para:SOFI", maxLeverage: 10, szDecimals: 2 }] },
    newdex: { collateralToken: 0, universe: [{ name: "newdex:NEW", maxLeverage: 5, szDecimals: 3 }] },
  };
  const reader = async (body: Record<string, unknown>) => body.type === "perpDexs" ? dexs : metadata[String(body.dex)];
  for (const [coin, ticker] of [["xyz:NVDA", "NVDA"], ["para:SOFI", "SOFI"], ["newdex:NEW", "NEW"]]) {
    await verifyHip3Market(validateIntent({ ...intent, coin, ticker }, now), reader);
  }
  for (const patch of [{ coin: "para:SOFI", ticker: "NVDA" }, { coin: "xyz:SOFI", ticker: "SOFI" },
    { coin: "fake:NVDA", ticker: "NVDA" }, { coin: "spot:NVDA", ticker: "NVDA" }]) {
    await rejects(() => verifyHip3Market(validateIntent({ ...intent, ...patch }, now), reader));
  }
  for (const change of [{ isDelisted: true }, { maxLeverage: 0 }, { szDecimals: 7 }]) {
    const changed = { ...metadata.para, universe: [{ ...metadata.para.universe[0], ...change }] };
    await rejects(() => verifyHip3Market({ ...intent, coin: "para:SOFI", ticker: "SOFI" },
      async body => body.type === "perpDexs" ? dexs : changed));
  }
  await rejects(() => verifyHip3Market(intent, async body => body.type === "perpDexs" ? dexs :
    { ...metadata.xyz, collateralToken: 268 }));
  await rejects(() => verifyHip3Market(intent, async () => ({ malformed: true })));
});
Deno.test("old, wrong-market, wrong-direction, reduced and mismatched orders never publish", async () => {
  for (const patch of [{ timestamp: now - 10000 }, { coin: "xyz:MU" }, { side: "A" }, { reduceOnly: true },
    { origSz: "3" }, { limitPx: "130" }, { cloid: "0x" + "33".repeat(16) }, { isTrigger: true }, { tif: "Gtc" }]) {
    const s = status(); Object.assign(s.order.order, patch);
    await rejects(() => verifyExecution(record, info(s), now));
  }
});
Deno.test("resting rejected and unknown orders are not fills", async () => {
  for (const state of ["open", "rejected", "scheduledCancel"]) {
    const s = status(); s.order.status = state;
    assert(await verifyExecution(record, info(s), now) === null);
  }
  assert(await verifyExecution(record, async () => ({ status: "unknownOid" }), now) === null);
});
Deno.test("invalid or duplicate fill evidence fails closed", async () => {
  for (const patch of [{ coin: "xyz:MU" }, { side: "A" }, { sz: "0" }, { sz: "3" }, { px: "121" },
    { time: now - 10000 }, { time: now + 1 }, { hash: "0x" + "00".repeat(32) }, { tid: 1 }]) {
    const f = fills(); Object.assign(f[1], patch);
    await rejects(() => verifyExecution(record, info(status(), f), now));
  }
  await rejects(() => verifyExecution(record, info(status(), fills().slice(0, 1)), now));
  await rejects(() => verifyExecution(record, info(status(), Array(2000).fill(fills()[0])), now));
});
Deno.test("canceled IOC with verified partial fill counts; zero fill does not", async () => {
  const s = status(); s.order.status = "canceled";
  assert((await verifyExecution(record, info(s, fills().slice(0, 1)), now))?.notionalUSD === "110.1");
  assert(await verifyExecution(record, info(s, []), now) === null);
});
Deno.test("verifier queries only registered wallet and client order id", async () => {
  const requests: Record<string, unknown>[] = [];
  await verifyExecution(record, async body => { requests.push(body); return await info()(body); }, now);
  assert(requests.every(r => r.user === record.wallet)); assert(requests[0].oid === intent.cloid);
  assert(requests[1].aggregateByTime === false && requests[1].startTime === now - 4000);
});
Deno.test("decimal arithmetic does not round sub-cent fills", () => {
  assert(decimal("0.000000000000000001") === 1n);
  assert(decimal("1.1") * 2n === decimal("2.2"));
});
Deno.test("legacy sharing requests remain public and cannot overwrite platform identity", async () => {
  const user: any = { id: crypto.randomUUID(), identities: [{ provider: "google", identity_data: {
    avatar_url: "https://lh3.googleusercontent.com/example" } }] };
  const input = { nickname: "Mia", visible: false, feedVisible: false, useProviderAvatar: false };
  assert(!("avatar_url" in sharingInput(input, user)));
  assert(sharingInput(input, user).feed_visible);
  assert(sharingInput({ ...input, feedVisible: true }, user).visible);
  await rejects(() => sharingInput({ ...input, accountId: crypto.randomUUID() }, user));
  await rejects(() => sharingInput({ ...input, avatarURL: "https://evil.invalid/image" }, user));
  assert(!("nickname" in sharingInput({ ...input, visible: true, feedVisible: true }, user)));
  assert(sharingInput({ visible: true, feedVisible: true }).feed_visible);
});
Deno.test("no bearer, rejected bearer and anonymous identity cannot reach data", async () => {
  const deps = { info: info(), catalog: async () => ({}), markets: {} };
  const bad: any = { auth: { getUser: async () => ({ data: { user: null }, error: true }) },
    from() { throw new Error("must not reach database"); } };
  assert((await handleFeed(new Request("https://test.invalid/bsmart-feed"), bad, deps)).status === 401);
  const req = () => new Request("https://test.invalid/bsmart-feed", { headers: { Authorization: "Bearer a.b.c" } });
  assert((await handleFeed(req(), bad, deps)).status === 401);
  bad.auth.getUser = async () => ({ data: { user: { id: "test", is_anonymous: true, identities: [{ provider: "google" }] } } });
  assert((await handleFeed(req(), bad, deps)).status === 401);
});
Deno.test("read pages use guarded RPC and no-store, unavailable stays 503", async () => {
  const calls: any[] = [];
  const client: any = { auth: { getUser: async () => ({ data: { user: { id: crypto.randomUUID(), identities: [{ provider: "google" }] } } }) },
    rpc: (name: string, args: unknown) => { calls.push([name, args]); return { data: { items: [], nextOffset: null } }; } };
  const req = () => new Request("https://test.invalid/bsmart-feed?offset=0&limit=10", { headers: { Authorization: "Bearer a.b.c" } });
  const deps = { info: info(), catalog: async () => ({}), markets: {} };
  const result = await handleFeed(req(), client, deps);
  assert(result.status === 200 && result.headers.get("cache-control") === "no-store");
  assert(calls[0][0] === "bsmart_feed_page");
  client.rpc = () => ({ error: true });
  assert((await handleFeed(req(), client, deps)).status === 503);
});
Deno.test("public social feed supports missing migration without masking private or operational failures", async () => {
  const calls: any[] = [];
  let code = "PGRST202";
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: crypto.randomUUID(), identities: [{ provider: "google" }] } } }) },
    rpc: (name: string, args: unknown) => {
      calls.push([name, args]);
      return name === "bsmart_feed_social_page" ? { error: { code } } : { data: { items: [], nextOffset: null } };
    },
  };
  const deps = { info: info(), catalog: async () => ({}), markets: {} };
  const request = (extra = "") => new Request("https://test.invalid/bsmart-feed?includeTheses=true&offset=10&limit=10" + extra,
    { headers: { Authorization: "Bearer a.b.c" } });
  const profile = crypto.randomUUID();
  assert((await handleFeed(request("&profileId=" + profile), client, deps)).status === 200);
  assert(calls[1][0] === "bsmart_feed_page" && calls[1][1].p_profile === profile && calls[1][1].p_offset === 10);
  calls.length = 0;
  assert((await handleFeed(request("&mine=true"), client, deps)).status === 503);
  assert(calls.length === 1);
  calls.length = 0;
  code = "42501";
  assert((await handleFeed(request(), client, deps)).status === 503);
  assert(calls.length === 1);
});
Deno.test("registration binds authenticated owner before any fill and is immutable", async () => {
  const account = crypto.randomUUID(), writes: any[] = [];
  let stored: any = null;
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: account, identities: [{ provider: "google" }] } } }) },
    from: (table: string) => {
      let insert: any;
      const query: any = {
        select: () => query, eq: () => query, gte: () => query,
        maybeSingle: () => Promise.resolve({ data: table === "bsmart_wallets" ? { address: record.wallet } : stored }),
        insert: (value: any) => { insert = value; return query; },
        single: () => { writes.push(insert); stored = { ...insert, id: crypto.randomUUID() }; return { data: stored }; },
        then: (resolve: (value: unknown) => unknown) => Promise.resolve(resolve({ count: 0 })),
      };
      return query;
    },
  };
  let infoCalls = 0;
  const deps = { now: () => now,
    info: async (body: Record<string, unknown>) => { infoCalls++;
      if (body.type === "perpDexs") return [null, { name: "xyz" }];
      if (body.type === "meta") return { collateralToken: 0, universe: [{ name: "xyz:NVDA", maxLeverage: 20, szDecimals: 2 }] };
      return { status: "unknownOid" }; },
    catalog: async () => ({ id: intent.opinionId, authorId: intent.authorId, ticker: intent.ticker,
      platformPercentile: .1, publishedAt: new Date(now - 86400000).toISOString() }) };
  const req = (value: any = intent) => new Request("https://test.invalid/bsmart-feed/orders", {
    method: "POST", headers: { Authorization: "Bearer a.b.c", "Content-Type": "application/json" }, body: JSON.stringify(value),
  });
  assert((await handleFeed(req(), client, deps)).status === 200);
  assert(writes.length === 1 && writes[0].account_id === account && writes[0].wallet === record.wallet);
  assert(!("execution" in writes[0]) && !("registered_at" in writes[0]));
  assert((await handleFeed(req(), client, deps)).status === 200);
  assert(writes.length === 1 && infoCalls === 3);
  assert((await handleFeed(req({ ...intent, size: "3" }), client, deps)).status === 409);
  assert((await handleFeed(req({ ...intent, accountId: crypto.randomUUID() }), client, deps)).status === 422);
  stored = null;
  deps.info = async () => ({ status: "order" });
  assert((await handleFeed(req(), client, deps)).status === 409);
  assert(writes.length === 1);
  deps.info = async body => body.type === "perpDexs" ? [null, { name: "xyz" }]
    : body.type === "meta" ? { collateralToken: 0, universe: [] }
    : { status: "unknownOid" };
  const unavailable = await handleFeed(req(), client, deps);
  assert(unavailable.status === 422 && (await unavailable.json()).error === "market_unavailable");
  assert(writes.length === 1);
});

Deno.test("catalog gaps and expiry during verification never write an order", async () => {
  let writes = 0;
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: crypto.randomUUID(), identities: [{ provider: "google" }] } } }) },
    from: (table: string) => {
      const query: any = {
        select: () => query, eq: () => query, gte: () => query,
        maybeSingle: async () => ({ data: table === "bsmart_wallets" ? { address: record.wallet } : null }),
        insert: () => { writes++; throw Error("must not write"); },
        then: (resolve: (value: unknown) => unknown) => Promise.resolve(resolve({ count: 0 })),
      };
      return query;
    },
  };
  for (const missing of [true, false]) {
    let time = now;
    const response = await handleFeed(new Request("https://test/bsmart-feed/orders", {
      method: "POST", headers: { Authorization: "Bearer a.b.c", "Content-Type": "application/json" }, body: JSON.stringify(intent),
    }), client, {
      now: () => time, info: async body => body.type === "perpDexs" ? [null, { name: "xyz" }]
        : body.type === "meta" ? { collateralToken: 0, universe: [{ name: "xyz:NVDA", maxLeverage: 20, szDecimals: 2 }] }
        : { status: "unknownOid" },
      catalog: async () => {
        if (missing) throw Error("opinion_unavailable");
        time = intent.expiresAfter;
        return { id: intent.opinionId, authorId: intent.authorId, ticker: intent.ticker,
          platformPercentile: .1, publishedAt: new Date(now - 1000).toISOString() };
      },
    });
    assert(response.status === 422);
    assert((await response.json()).error === (missing ? "opinion_unavailable" : "invalid_input"));
  }
  assert(writes === 0);
});

Deno.test("popular opinions require auth, bound pagination and never query the exchange", async () => {
  const calls: any[] = [];
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: crypto.randomUUID(), identities: [{ provider: "google" }] } } }) },
    rpc: (name: string, args: any) => { calls.push([name, args]); return { data: { items: [], nextOffset: null, windowDays: 7 } }; },
  };
  const deps = { markets: {}, catalog: async () => ({}), info: async () => { throw Error("no exchange reads"); } };
  const request = (query = "offset=0&limit=10", auth = true) => new Request("https://test.invalid/bsmart-feed/popular?" + query,
    { headers: auth ? { Authorization: "Bearer a.b.c" } : {} });
  assert((await handleFeed(request("", false), client, deps)).status === 401);
  assert((await handleFeed(request("limit=999"), client, deps)).status === 422);
  assert(calls.length === 0);
  const result = await handleFeed(request(), client, deps);
  assert(result.status === 200 && result.headers.get("cache-control") === "no-store");
  assert(calls[0][0] === "bsmart_feed_popular" && calls[0][1].p_offset === 0 && calls[0][1].p_limit === 10);
  client.rpc = () => ({ error: true });
  assert((await handleFeed(request(), client, deps)).status === 503);
});

Deno.test("migration denies direct client writes and uses anonymous public IDs", async () => {
  const sql = await Deno.readTextFile(new URL("../supabase/migrations/202609120002_trade_feed.sql", import.meta.url));
  assert(sql.includes("from anon, authenticated")); assert(sql.includes("enable row level security"));
  assert(sql.includes("public_id uuid not null default gen_random_uuid() unique"));
  assert(sql.includes("p.visible and p.feed_visible"));
  assert(sql.includes("on delete cascade"));
  assert(!sql.includes("'accountId'")); assert(!sql.includes("'wallet'"));
});
