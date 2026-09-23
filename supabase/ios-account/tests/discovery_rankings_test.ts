import { strict as assert } from "node:assert";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";
import { handleFeed } from "../supabase/functions/bsmart-feed/handler.ts";

Deno.test("rankings validate filters, auth and anchors before querying", async () => {
  let calls = 0;
  const now = Date.parse("2026-09-22T10:00:00Z");
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: crypto.randomUUID(), identities: [{ provider: "google" }] } } }) },
    rpc: (name: string, args: any) => {
      calls++; assert.equal(name, "bsmart_discovery_rankings");
      assert.equal(args.p_kind, "investors"); assert.equal(args.p_limit, 3);
      assert.equal(args.p_as_of, new Date(now).toISOString());
      return { data: { items: [], nextOffset: null } };
    },
  };
  const deps = { now: () => now, markets: {}, catalog: async () => ({}), info: async () => { throw Error("no exchange reads"); } };
  const request = (query: string, authenticated = true) => new Request("https://test.invalid/bsmart-feed/rankings?" + query,
    { headers: authenticated ? { Authorization: "Bearer a.b.c" } : {} });
  const query = "kind=investors&sort=volume&window=7d&limit=3";
  assert.equal((await handleFeed(request(query, false), client, deps)).status, 401);
  for (const invalid of ["", query + "&asOf=tomorrow", query + "&asOf=2099-01-01", query.replace("7d", "2d"), query.replace("volume", "likes"), query.replace("3", "31")]) {
    assert.equal((await handleFeed(request(invalid), client, deps)).status, 422);
  }
  assert.equal(calls, 0);
  const response = await handleFeed(request(query), client, deps);
  assert.equal(response.status, 200); assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(calls, 1);
  client.rpc = () => ({ error: true });
  assert.equal((await handleFeed(request(query), client, deps)).status, 503);
});

Deno.test("rankings SQL deduplicates investors across opinions, sums exact volumes and filters periods", async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create table auth.users(id uuid primary key);`);
    const root = new URL("../supabase/migrations/", import.meta.url);
    await db.exec(await Deno.readTextFile(new URL("202609120002_trade_feed.sql", root)));
    await db.exec(await Deno.readTextFile(new URL("202609220003_discovery_rankings.sql", root)));
    const a = crypto.randomUUID(), b = crypto.randomUUID();
    await db.query("insert into auth.users values ($1),($2)", [a,b]);
    await db.exec("set role service_role");
    const opinionA = crypto.randomUUID(), opinionB = crypto.randomUUID(), opinionC = crypto.randomUUID();
    const insert = async (user: string, opinion: string, author: string, amount: string, age = "1 hour", side = "long", platform = "X", extra = {}) => {
      const id = crypto.randomUUID();
      await db.query(`insert into public.bsmart_feed_orders(id,account_id,wallet,cloid,opinion_id,intent,opinion,execution,last_filled_at)
        values($1::uuid,$2,'wallet',($1::uuid)::text,$3,'{}',$4,$5,now()-$6::interval)`,
        [id,user,opinion,JSON.stringify({ authorId: author, authorName: author, platform, platformPercentile: .1, ...extra }),
          JSON.stringify({ side, notionalUSD: amount }),age]);
      return id;
    };
    await insert(a,opinionA,"alpha","0.1","2 hours");
    await insert(a,opinionB,"alpha","0.2","1 hour","short");
    await insert(b,opinionA,"alpha","1","3 hours");
    await insert(a,opinionC,"beta","100","2 days");
    await insert(b,crypto.randomUUID(),"old","1000","40 days");
    await insert(a,crypto.randomUUID(),"future","500","-1 day");
    await insert(a,crypto.randomUUID(),"unranked","500","1 hour","long","X", {platformPercentile: .7});
    await insert(a,crypto.randomUUID(),"money","500","1 hour","long","Hyperliquid", {sourceKind: "money"});
    const pending = await insert(a,crypto.randomUUID(),"pending","500");
    await db.query("update public.bsmart_feed_orders set execution=null where id=$1",[pending]);
    const page = async (kind = "investors", sort = "traders", window = "7d", offset = 0, limit = 30) =>
      (await db.query<any>("select public.bsmart_discovery_rankings($1,$2,$3,now(),$4,$5) as page",[kind,sort,window,offset,limit])).rows[0].page;
    let result = await page();
    assert.equal(result.items.length,2);
    assert.equal(result.items[0].id,"x:alpha");
    assert.equal(result.items[0].totalTraders,2);
    assert.equal(result.items[0].opinionCount,2);
    assert.equal(result.items[0].totalNotionalUSD,"1.3");
    assert.equal(result.items[0].longTraders,1); assert.equal(result.items[0].shortTraders,1);
    assert.equal((await page("investors","volume")).items[0].id,"x:beta");
    assert.equal((await page("investors","volume","1d")).items.length,1);
    assert.equal((await page("investors","volume","30d")).items.length,2);
    assert.equal((await page("investors","volume","all")).items[0].id,"x:old");
    result = await page("opinions"); assert.equal(result.items.length,3);
    assert.equal(result.items[0].id,opinionA); assert.equal(result.items[0].totalTraders,2);
    const first = await page("opinions","traders","7d",0,1);
    const second = await page("opinions","traders","7d",1,1);
    assert.equal(first.nextOffset,1); assert.notEqual(first.items[0].id,second.items[0].id);
    await insert(a,crypto.randomUUID(),"broken","NaN");
    assert.equal((await page()).items.find((i: any) => i.id === "x:broken").totalNotionalUSD,null);
    assert(!(await page("investors","volume")).items.some((i: any) => i.id === "x:broken"));
    await insert(a,crypto.randomUUID(),"alpha","2","1 hour","long","YouTube");
    await insert(a,crypto.randomUUID(),"alpha","3","1 hour","long","Reddit");
    assert((await page()).items.some((i: any) => i.id === "youtube:alpha"));
    assert((await page()).items.some((i: any) => i.id === "reddit:alpha"));
    await db.exec("set role authenticated");
    await assert.rejects(() => page(), /permission denied/);
  } finally { await db.close(); }
});
