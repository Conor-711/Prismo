import { strict as assert } from "node:assert";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";
import { handleFeed } from "../supabase/functions/bsmart-feed/handler.ts";
import { subjectScope, validCatalogSource } from "../supabase/functions/bsmart-feed/subject.ts";
import type { Intent } from "../supabase/functions/bsmart-feed/verification.ts";

Deno.test("subject totals count user/source pairs, not unique people or repeated fills", async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create table auth.users(id uuid primary key);`);
    const root = new URL("../supabase/migrations/", import.meta.url);
    await db.exec(await Deno.readTextFile(new URL("202609120002_trade_feed.sql", root)));
    await db.exec(await Deno.readTextFile(new URL("202609130001_subject_trade_stats.sql", root)));
    const a = crypto.randomUUID(), b = crypto.randomUUID();
    await db.query("insert into auth.users values ($1),($2)", [a, b]);
    const ids = Array.from({ length: 10 }, () => crypto.randomUUID());
    let sequence = 0;
    const insert = async (user: string, source: string, side = "long", extra: any = {}, verified = true) => {
      await db.query(`insert into public.bsmart_feed_orders(account_id,wallet,cloid,opinion_id,intent,
        opinion,execution,last_filled_at) values($1,'not-a-real-wallet',$2,$3,'{}',$4,$5,$6)`,
        [user, crypto.randomUUID(), source, JSON.stringify({ authorId: "author", platform: "X", ...extra }),
          verified ? JSON.stringify({ side }) : null, new Date(1700000000000 + sequence++ * 1000).toISOString()]);
    };
    const stats = async (kind = "account", platform = "X", author = "author") =>
      (await db.query<any>("select public.bsmart_subject_trade_stats($1,$2,$3) as result", [kind, author, platform])).rows[0].result;
    for (const [i, id] of ids.entries()) await insert(a, id, i < 7 ? "long" : "short");
    assert.deepEqual(await stats(), { kind: "account", subjectId: "author", platform: "X",
      totalTrades: 10, longTrades: 7, shortTrades: 3, sourceCount: 10 });
    await insert(a, ids[0], "short");
    assert.equal((await stats()).totalTrades, 10);
    assert.equal((await stats()).shortTrades, 4, "latest direction wins once per pair");
    await insert(a, crypto.randomUUID(), "long", {}, false);
    assert.equal((await stats()).totalTrades, 10, "registration without verified fill never counts");
    await insert(b, ids[0]);
    assert.equal((await stats()).totalTrades, 11);
    await insert(a, crypto.randomUUID(), "long", { platform: "YouTube" });
    await insert(a, crypto.randomUUID(), "long", { authorId: "other-author" });
    await insert(a, crypto.randomUUID(), "short", { sourceKind: "money", platform: "hyperliquid" });
    assert.equal((await stats()).totalTrades, 11);
    assert.equal((await stats("money", "hyperliquid")).totalTrades, 1);
    assert.equal((await stats("account", "X", "missing")).totalTrades, 0);
    await db.query("delete from auth.users where id=$1", [a]);
    assert.equal((await stats()).totalTrades, 1, "deleted user's contributions cascade away");
    await db.exec("set role authenticated");
    await assert.rejects(stats);
    await db.exec("reset role; set role service_role");
    assert.equal((await stats()).totalTrades, 1);
  } finally { await db.close(); }
});

Deno.test("subject route scopes RPC, validates query and preserves unavailable state", async () => {
  assert.equal(subjectScope(new URL("https://example.com?kind=account&id=author&platform=%E9%9B%AA%E7%90%83")).p_platform, "\u96ea\u7403");
  const calls: any[] = [];
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { identities: [{ provider: "google" }] } } }) },
    rpc: (name: string, args: any) => { calls.push([name, args]); return { data: { totalTrades: 0 } }; },
  };
  const deps = { markets: {}, catalog: async () => ({}), info: async () => { throw Error("no exchange calls"); } };
  const request = (query: string, auth = true) => new Request("https://example.com/bsmart-feed/subject-stats?" + query,
    { headers: auth ? { authorization: "Bearer a.b.c" } : {} });
  const query = "kind=account&id=author&platform=X";
  assert.equal((await handleFeed(request(query, false), client, deps)).status, 401);
  for (const invalid of ["kind=wrong&id=a&platform=X", "kind=money&id=a&platform=X", "kind=account&id=a", "kind=account&id=%00&platform=X"]) {
    assert.equal((await handleFeed(request(invalid), client, deps)).status, 422);
  }
  assert.equal(calls.length, 0);
  const response = await handleFeed(request(query), client, deps);
  assert.equal(response.status, 200); assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(calls[0], ["bsmart_subject_trade_stats", { p_kind: "account", p_subject: "author", p_platform: "X" }]);
  client.rpc = () => ({ error: true });
  assert.equal((await handleFeed(request(query), client, deps)).status, 503);
});

Deno.test("money source is server-classified and must match exact market and observed time", () => {
  const now = Date.now(), intent = { opinionId: crypto.randomUUID(), authorId: "money", ticker: "NVDA", coin: "xyz:NVDA" } as Intent;
  const source = { id: intent.opinionId, authorId: "money", ticker: "NVDA", sourceKind: "money", platform: "hyperliquid",
    publishedAt: new Date(now - 1000).toISOString(), marketCoin: "xyz:NVDA" };
  assert.ok(validCatalogSource(source, intent, now));
  for (const patch of [{ sourceKind: "unknown" }, { authorId: "other" }, { marketCoin: "other:NVDA" },
    { platform: "X" }, { publishedAt: new Date(now + 1000).toISOString() }, { platformPercentile: .1 }]) {
    assert.equal(validCatalogSource({ ...source, ...patch }, intent, now), false);
  }
});
