import { strict as assert } from "node:assert";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";
import { type DirectIntent, validateDirectIntent, verifyDirectMarket, verifyExecution } from "../supabase/functions/bsmart-feed/verification.ts";
import { handleFeed } from "../supabase/functions/bsmart-feed/handler.ts";
import { enrichNativeInvestors } from "../supabase/functions/bsmart-feed/native_investors.ts";
import { activityReference, verifiedActivity } from "../supabase/functions/bsmart-feed/activity_source.ts";

const migration = new URL("../supabase/migrations/", import.meta.url);
const now = 1800000000000;
const direct: DirectIntent = { ticker: "NVDA", cloid: "0x" + "1".repeat(32), coin: "xyz:NVDA",
  side: "sell", size: "2", limitPrice: "120", nonce: now - 5000,
  expiresAfter: now + 55000, reduceOnly: true };

Deno.test("direct intent cannot forge identity or skip a verified close", async () => {
  assert.deepEqual(validateDirectIntent(direct, now), direct);
  for (const patch of [{ accountId: crypto.randomUUID() }, { opinionId: crypto.randomUUID() },
    { reduceOnly: "true" }, { size: "0" }]) {
    assert.throws(() => validateDirectIntent({ ...direct, ...patch }, now));
  }
  const record = { id: crypto.randomUUID(), wallet: "0x" + "2".repeat(40), intent: direct,
    registered_at: new Date(now - 4000).toISOString() };
  const status = { status: "order", order: { status: "filled", statusTimestamp: now - 1000,
    order: { cloid: direct.cloid, coin: direct.coin, side: "A", origSz: "2", limitPx: "120",
      reduceOnly: true, isTrigger: false, tif: "Ioc", oid: 17, timestamp: now - 3000 } } };
  const fill = { tid: 1, oid: 17, coin: direct.coin, side: "A", px: "121", sz: "2",
    time: now - 2000, hash: "0x" + "ab".repeat(32), closedPnl: "4.5", fee: "0.1" };
  const info = async (query: Record<string, unknown>) => query.type === "orderStatus" ? status : [fill];
  const result = await verifyExecution(record, info, now);
  assert.equal(result?.netRealizedPnlUSD, "4.4");
  assert.equal(result?.feeUSD, "0.1");
  assert.equal(result?.reduceOnly, true);
  assert.equal(result?.notionalUSD, "242");
  status.order.order.reduceOnly = false;
  await assert.rejects(() => verifyExecution(record, info, now));
  const core = validateDirectIntent({ ...direct, ticker: "BTC", coin: "BTC" }, now);
  assert.equal(core.coin, "BTC");
  let queriedCore = false;
  await verifyDirectMarket(core, async query => {
    assert.deepEqual(query, { type: "meta", dex: "" });
    queriedCore = true;
    return { universe: [{ name: "BTC", maxLeverage: 40, szDecimals: 5 }] };
  });
  assert.equal(queriedCore, true);
  await assert.rejects(() => verifyDirectMarket({ ...core, ticker: "ETH" }, async () => ({})));
});

Deno.test("direct registration binds the wallet owner and persists no client-side execution", async () => {
  const actor = crypto.randomUUID(), wallet = "0x" + "3".repeat(40), writes: any[] = [];
  let stored: any = null;
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: actor, identities: [{ provider: "apple" }] } } }) },
    from: (table: string) => {
      let inserted: any;
      const query: any = {
        select: () => query, eq: () => query, gte: () => query,
        maybeSingle: async () => ({ data: table === "bsmart_wallets" ? { address: wallet } : stored }),
        insert: (value: any) => { inserted = value; return query; },
        single: async () => { writes.push(inserted); stored = { ...inserted, id: crypto.randomUUID() }; return { data: stored }; },
        then: (resolve: (value: unknown) => unknown) => Promise.resolve(resolve({ count: 0 })),
      };
      return query;
    },
  };
  const deps = {
    now: () => now,
    info: async (query: Record<string, unknown>) => query.type === "perpDexs" ? [null, { name: "xyz" }]
      : query.type === "meta" ? { collateralToken: 0,
        universe: [{ name: "xyz:NVDA", maxLeverage: 20, szDecimals: 2 }] }
      : { status: "unknownOid" },
    catalog: async () => { throw Error("direct trades must not query the opinion catalog"); },
  };
  const request = (intent: unknown) => new Request("https://test.invalid/bsmart-feed/orders/direct", {
    method: "POST", headers: { Authorization: "Bearer a.b.c", "Content-Type": "application/json" },
    body: JSON.stringify(intent),
  });
  assert.equal((await handleFeed(request(direct), client, deps)).status, 200);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].account_id, actor);
  assert.equal(writes[0].wallet, wallet);
  assert.equal(writes[0].source_kind, "direct");
  assert.equal(writes[0].opinion, null);
  assert.equal(writes[0].execution, undefined);
  assert.equal((await handleFeed(request(direct), client, deps)).status, 200);
  assert.equal(writes.length, 1);
  assert.equal((await handleFeed(request({ ...direct, accountId: crypto.randomUUID() }), client, deps)).status, 422);
  assert.equal((await handleFeed(request({ ...direct, size: "3" }), client, deps)).status, 409);

  stored = null;
  const event = { id: "filing-1", subjectID: "politician:member-1", ticker: "NVDA",
    type: "trade", action: "sell", summary: "Sold NVDA" };
  client.rpc = async () => ({ data: { subjects: [{ id: event.subjectID, name: "Member One" }],
    events: [event] }, error: null });
  const sourced = { ...direct, cloid: "0x" + "4".repeat(32), reduceOnly: false,
    source: { kind: "subject", subjectID: event.subjectID, eventID: event.id } };
  assert.equal((await handleFeed(request(sourced), client, deps)).status, 200);
  assert.deepEqual(writes.at(-1).intent.baseActivity, {
    kind: "subject", subjectID: event.subjectID, eventID: event.id,
    authorName: "Member One", avatarURL: null, body: "Sold NVDA", subjectEvent: event,
  });
  assert.equal((await handleFeed(request({ ...sourced, source: { ...sourced.source,
    eventID: "another-event" } }), client, deps)).status, 409);
});

Deno.test("native investor snapshot route returns the verified projection", async () => {
  const snapshot = { profiles: [{ publicID: crypto.randomUUID(), nickname: "Connor", avatarURL: null }],
    updates: [{ id: crypto.randomUUID(), ticker: "ORCL", reducing: null },
      { id: crypto.randomUUID(), ticker: "NVDA", reducing: true }] };
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: crypto.randomUUID(), identities: [{ provider: "apple" }] } } }) },
    rpc: async (name: string) => {
      assert.equal(name, "bsmart_native_investor_snapshot");
      return { data: snapshot, error: null };
    },
    from: () => ({ select: () => ({ in: async () => ({ data: null, error: { message: "temporary failure" } }) }) }),
  };
  const request = new Request("https://test.invalid/bsmart-feed/investors/snapshot", {
    headers: { Authorization: "Bearer a.b.c" },
  });
  const response = await handleFeed(request, client, { info: async () => null, catalog: async () => null });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ...snapshot, updates: [
    { ...snapshot.updates[0], reducing: false }, snapshot.updates[1],
  ] });
});

Deno.test("subject attribution resolves published activity and rejects mismatched tickers", async () => {
  const subjectID = "politician:kevin-hern", eventID = "filing-1";
  const event = { id: eventID, subjectID, ticker: "AAPL", type: "trade", action: "sell",
    summary: "Sold Apple shares", occurredDay: "2026-09-08", displayDay: "2026-09-25",
    isSample: false };
  const client: any = { rpc: async (name: string, args: any) => {
    assert.equal(name, "bsmart_subject_activity_read");
    assert.equal(args.p_subject_id, subjectID);
    return { data: { subjects: [{ id: subjectID, name: "Kevin Hern", avatarURL: null }],
      events: [event] }, error: null };
  } };
  const source = activityReference({ kind: "subject", subjectID, eventID });
  assert(source);
  assert.deepEqual(await verifiedActivity(client, source, "AAPL"), {
    kind: "subject", subjectID, eventID, authorName: "Kevin Hern", avatarURL: null,
    body: "Sold Apple shares", subjectEvent: event,
  });
  await assert.rejects(() => verifiedActivity(client, source, "NVDA"), /source_unavailable/);
  assert.throws(() => activityReference({ kind: "subject", subjectID, eventID,
    body: "forged trade" }), /invalid_input/);
});

Deno.test("holding attribution permits only the published underlying, retaining the option event", async () => {
  for (const kind of ["celebrity", "institution"]) {
    const subjectID = `${kind}:investor`, eventID = "option-filing";
    const event: any = { id: eventID, subjectID, ticker: null, underlyingTicker: "TSLA",
      type: "holding", action: "increased", summary: "PUT option", isSample: false };
    const client: any = { rpc: async () => ({ data: {
      subjects: [{ id: subjectID, name: "Investor" }], events: [event],
    }, error: null }) };
    const source = activityReference({ kind: "subject", subjectID, eventID });
    assert(source);
    const base = await verifiedActivity(client, source, "TSLA");
    assert.deepEqual(base.subjectEvent, event);
    assert.equal(base.eventID, eventID);
    await assert.rejects(() => verifiedActivity(client, source, "NVDA"), /source_unavailable/);
    event.type = "trade";
    await assert.rejects(() => verifiedActivity(client, source, "TSLA"), /source_unavailable/);
    event.type = "holding";
    event.ticker = "AAPL";
    await assert.rejects(() => verifiedActivity(client, source, "TSLA"), /source_unavailable/);
    await verifiedActivity(client, source, "AAPL");
  }
});

Deno.test("native attribution resolves only published matching updates", async () => {
  const id = crypto.randomUUID();
  const client: any = { rpc: async (name: string) => {
    assert.equal(name, "bsmart_native_investor_snapshot");
    return { data: { updates: [{ id, publicID: crypto.randomUUID(), nickname: "Trader",
      avatarURL: null, body: "Bought NVDA", ticker: "NVDA", reducing: false,
      side: "long", publishedAt: "2026-09-30T09:00:00Z" }] }, error: null };
  } };
  const source = activityReference({ kind: "native", updateID: id.toUpperCase() });
  assert(source);
  const base = await verifiedActivity(client, source, "NVDA");
  assert.equal(base.kind, "native");
  assert.equal(base.body, "Bought NVDA");
  await assert.rejects(() => verifiedActivity(client, source, "AAPL"), /source_unavailable/);
});

Deno.test("native trade details use verified fills, live position and the stored base opinion", async () => {
  const openID = crypto.randomUUID(), closeID = crypto.randomUUID();
  const opinionID = crypto.randomUUID();
  const wallet = "0x" + "a".repeat(40);
  const orders = [
    { id: openID, source_kind: "opinion", wallet, registered_at: "2026-09-30T09:00:00Z",
      intent: { coin: "xyz:ORCL", side: "buy", size: "2" },
      execution: { marketCoin: "xyz:ORCL", side: "long", notionalUSD: "276",
        orderID: "11", fillIDs: ["101"], lastFilledAt: "2026-09-30T09:01:00Z" },
      opinion: { id: opinionID, authorId: "analyst-1", ticker: "ORCL", companyName: "Oracle",
        platform: "x", direction: "bullish", publishedAt: "2026-09-30T08:00:00Z",
        sourceURL: "https://example.com/original", authorName: "Analyst",
        authorAvatarURL: "https://example.com/avatar.jpg",
        originalText: "Original analysis on ORCL", thesis: "Summary" } },
    { id: closeID, source_kind: "direct", wallet, registered_at: "2026-09-30T09:30:00Z",
      intent: { coin: "xyz:NVDA", side: "sell", size: "1", reduceOnly: true },
      execution: { marketCoin: "xyz:NVDA", side: "short", notionalUSD: "130",
        netRealizedPnlUSD: "8.25", orderID: "12", fillIDs: ["102"],
        lastFilledAt: "2026-09-30T09:31:00Z" }, opinion: null },
  ];
  const client: any = { from: (table: string) => {
    assert.equal(table, "bsmart_feed_orders");
    return { select: () => ({ in: async (_column: string, ids: string[]) => ({
      data: orders.filter(order => ids.includes(order.id)), error: null,
    }) }) };
  } };
  const info = async (query: Record<string, unknown>) => {
    if (query.type === "clearinghouseState") return { assetPositions: [{ type: "oneWay", position: {
      coin: "xyz:ORCL", szi: "2", positionValue: "280", unrealizedPnl: "4",
      entryPx: "138", leverage: { value: 5 },
    } }] };
    assert.equal(query.type, "userFillsByTime");
    return [{ tid: 101, oid: 11, coin: "xyz:ORCL", sz: "2", px: "138", time: Date.parse("2026-09-30T09:01:00Z") },
      { tid: 102, oid: 12, coin: "xyz:NVDA", sz: "1", px: "130", time: Date.parse("2026-09-30T09:31:00Z") }];
  };
  const result = await enrichNativeInvestors(client, info, { profiles: [], updates: [
    { id: openID, reducing: null }, { id: closeID, reducing: true },
  ] });
  assert.deepEqual(result.updates[0].trade, {
    sourceKind: "opinion", eventKind: "opening", status: "open", marketCoin: "xyz:ORCL", side: "long",
    notionalUSD: "276", leverage: 5,
    unrealizedPnlUSD: "4", realizedPnlUSD: null, entryPriceUSD: "138",
    currentPriceUSD: "140", exitPriceUSD: null,
    base: { kind: "opinion", opinionID, authorID: "analyst-1", ticker: "ORCL", companyName: "Oracle",
      platform: "x", direction: "bullish", publishedAt: "2026-09-30T08:00:00Z",
      sourceURL: "https://example.com/original", thesis: "Summary", authorName: "Analyst",
      avatarURL: "https://example.com/avatar.jpg", body: "Original analysis on ORCL" },
  });
  assert.deepEqual(result.updates[1].trade, {
    sourceKind: "direct", eventKind: "closing", status: "closed", marketCoin: "xyz:NVDA", side: "long",
    notionalUSD: "130", leverage: null,
    unrealizedPnlUSD: null, realizedPnlUSD: "8.25", entryPriceUSD: null,
    currentPriceUSD: null, exitPriceUSD: "130", base: null,
  });
});

Deno.test("native investors are projected only from verified orders and published theories", async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create table auth.users(id uuid primary key);`);
    await db.exec(await Deno.readTextFile(new URL("202609120002_trade_feed.sql", migration)));
    await db.exec("alter table public.bsmart_feed_profiles add column handle text default 'handle', add column bio text default ''; ");
    await db.exec(await Deno.readTextFile(new URL("202609220004_trade_theses.sql", migration)));
    await db.exec(await Deno.readTextFile(new URL("202609280001_native_investors.sql", migration)));
    const owner = crypto.randomUUID(), hidden = crypto.randomUUID();
    await db.query("insert into auth.users values($1),($2)", [owner, hidden]);
    await db.query(`insert into public.bsmart_feed_profiles(account_id,nickname,handle,visible,feed_visible)
      values($1,'Connor','imconnorzhang',true,true),($2,'Hidden','hidden',false,false)`, [owner, hidden]);
    const trade = crypto.randomUUID(), close = crypto.randomUUID(), privateTrade = crypto.randomUUID();
    const opening = JSON.stringify({ ticker: "NVDA", side: "buy", reduceOnly: false });
    const closing = JSON.stringify({ ticker: "NVDA", side: "sell", reduceOnly: true });
    const openFill = JSON.stringify({ side: "long", marketCoin: "xyz:NVDA", notionalUSD: "100", feeUSD: "0.1" });
    const closeFill = JSON.stringify({ side: "short", marketCoin: "xyz:NVDA", notionalUSD: "110",
      realizedPnlUSD: "10", netRealizedPnlUSD: "9.9", feeUSD: "0.1", reduceOnly: true });
    for (const [id, actor, intent, execution] of [[trade, owner, opening, openFill],
        [close, owner, closing, closeFill], [privateTrade, hidden, opening, openFill]]) {
      await db.query(`insert into public.bsmart_feed_orders(id,account_id,wallet,cloid,source_kind,intent,execution,
        executed_at) values($1::uuid,$2::uuid,'wallet',$1::text,'direct',$3::jsonb,$4::jsonb,now())`,
        [id, actor, intent, execution]);
    }
    await db.exec("set role service_role");
    const publish = (id: string, actor: string) => db.query<{ result: any }>(
      "select public.bsmart_thesis_publish($1,$2,'Strong conviction on NVDA') result", [actor, id]);
    assert.equal((await publish(trade, owner)).rows[0].result.body, "Strong conviction on NVDA");
    await publish(privateTrade, hidden);
    const snapshot = (await db.query<{ value: any }>(
      "select public.bsmart_native_investor_snapshot() value")).rows[0].value;
    assert.equal(snapshot.profiles.length, 1);
    assert.equal(snapshot.profiles[0].handle, "imconnorzhang");
    assert.equal(snapshot.profiles[0].closedTrades, 1);
    assert.equal(snapshot.profiles[0].wins, 1);
    assert.equal(snapshot.profiles[0].netPnlUSD, 9.8);
    assert.equal(snapshot.profiles[0].rank, null);
    assert.equal(snapshot.updates.length, 1);
    assert.equal(snapshot.updates[0].body, "Strong conviction on NVDA");
    const feed = (await db.query<{ value: any }>(
      "select public.bsmart_feed_social_page($1,0,10) value", [owner])).rows[0].value;
    assert.equal(feed.items.length, 2);
    assert.equal(feed.items.find((item: any) => item.id === trade).opinion.sourceKind, "native_trade");
    assert.equal(feed.items.find((item: any) => item.id === close).canPublishThesis, true);
    assert.equal(feed.items.find((item: any) => item.id === close).opinion.direction, "neutral");
  } finally {
    await db.close();
  }
});
