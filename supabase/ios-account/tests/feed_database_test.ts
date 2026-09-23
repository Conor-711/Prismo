import { strict as assert } from "node:assert";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";

Deno.test("real Feed schema deduplicates people, respects consent and leases pending verification", async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create table auth.users(id uuid primary key);
      create table public.bsmart_wallets(account_id uuid primary key, address text);
      grant select on public.bsmart_wallets to service_role;`);
    const root = new URL("../supabase/migrations/", import.meta.url);
    await db.exec(await Deno.readTextFile(new URL("202609120002_trade_feed.sql", root)));
    const upgrade = await Deno.readTextFile(new URL("202609120003_feed_reconciliation.sql", root));
    // Hosted pg_cron/pg_net/Vault cannot run inside PGlite; queue/RLS/projection SQL can.
    await db.exec(upgrade.split("create extension if not exists pg_cron;")[0] + "commit;");
    await db.exec(await Deno.readTextFile(new URL("202609120004_feed_discovery.sql", root)));
    const a = crypto.randomUUID(), b = crypto.randomUUID(), opinion = crypto.randomUUID();
    await db.query("insert into auth.users values ($1),($2)", [a, b]);
    await db.query("insert into public.bsmart_feed_profiles(account_id,nickname,avatar_url) values($1,'Legacy Name','https://example.com/avatar.jpg')", [a]);
    const previous = (await db.query<any>("select * from public.bsmart_feed_profiles where account_id=$1", [a])).rows[0];
    await db.exec(await Deno.readTextFile(new URL("202609120005_account_profiles.sql", root)));
    await db.exec(await Deno.readTextFile(new URL("202609220001_opinion_trade_volume.sql", root)));
    const migrated = (await db.query<any>("select * from public.bsmart_feed_profiles where account_id=$1", [a])).rows[0];
    for (const key of ['public_id', 'nickname', 'avatar_url', 'visible', 'feed_visible']) assert.equal(migrated[key], previous[key]);
    await db.query("insert into public.bsmart_wallets values ($1,'wallet-a'),($2,'wallet-b')", [a, b]);
    await db.exec("set role service_role");
    const insert = async (account: string, percentile: number, execution: any = null) => {
      const id = crypto.randomUUID();
      await db.query(`insert into public.bsmart_feed_orders(id,account_id,wallet,cloid,opinion_id,intent,opinion,
        execution,executed_at,last_filled_at) values($1,$2,$3,$4,$5,'{}',$6,$7,now(),now())`,
        [id, account, account === a ? "wallet-a" : "wallet-b", id, opinion,
          JSON.stringify({ platformPercentile: percentile }), execution ? JSON.stringify(execution) : null]);
      return id;
    };
    const fill = { side: "long", notionalUSD: "16", marketCoin: "xyz:NVDA" };
    const first = await insert(a, .1, fill);
    await insert(a, .1, fill); const other = await insert(b, .8, { ...fill, side: "short" });
    const pending = await insert(a, .1);
    const people = async () => (await db.query<any>("select public.bsmart_opinion_traders($1,0,30) as page", [opinion])).rows[0].page;
    const feed = async () => (await db.query<any>("select public.bsmart_feed_page(0,10,null) as page")).rows[0].page;
    assert.equal((await people()).totalTraders, 2);
    assert.equal((await people()).totalNotionalUSD, "48", "Every verified fill contributes, including repeat orders");
    await db.query("update public.bsmart_feed_orders set execution=$2 where id=$1",
      [first, JSON.stringify({ ...fill, notionalUSD: "invalid" })]);
    assert.equal((await people()).totalNotionalUSD, null, "Incomplete historical amounts must not produce a partial total");
    await db.query("update public.bsmart_feed_orders set execution=$2 where id=$1", [first, JSON.stringify(fill)]);
    assert.equal((await people()).longTraders, 1);
    assert.equal((await people()).shortTraders, 1);
    assert.equal((await people()).publicTraders, 0);
    assert.equal((await feed()).items.length, 0);
    await db.query("update public.bsmart_feed_profiles set nickname='Casey',visible=true,feed_visible=true where account_id in ($1,$2)", [a, b]);
    const profiles = (await db.query<any>("select * from public.bsmart_feed_profiles order by account_id")).rows;
    assert.notEqual(profiles[0].handle, profiles[1].handle);
    await assert.rejects(() => db.query("update public.bsmart_feed_profiles set handle=$1 where account_id=$2", [profiles[0].handle, profiles[1].account_id]));
    await assert.rejects(() => db.query("update public.bsmart_feed_profiles set handle='UPPERCASE' where account_id=$1", [a]));
    await db.query("update public.bsmart_feed_profiles set handle='casey_one',bio='Investor' where account_id=$1", [a]);
    assert.equal((await feed()).items[0].trader.handle, 'casey_one');
    assert.equal((await people()).traders.find((p: any) => p.handle === 'casey_one').nickname, 'Casey');
    assert.equal((await people()).traders.length, 2);
    assert.equal((await feed()).items.length, 2, "Top 25% only, but people count accepts all scored authors");
    await db.query("update public.bsmart_feed_profiles set feed_visible=false where account_id=$1", [a]);
    assert.equal((await feed()).items.length, 0);
    assert.equal((await people()).publicTraders, 2, "Amount consent is independent from public name");
    await db.query("update public.bsmart_feed_profiles set visible=false where account_id=$1", [a]);
    assert.equal((await people()).publicTraders, 1);
    assert.equal((await people()).totalTraders, 2);
    await db.query("update public.bsmart_feed_orders set last_filled_at=clock_timestamp(),execution=$2 where id=$1",
      [first, JSON.stringify({ ...fill, side: "short" })]);
    assert.equal((await people()).shortTraders, 2, "Latest direction counts once, including private people");
    const popular = async (offset = 0, limit = 10) => (await db.query<any>(
      "select public.bsmart_feed_popular($1,$2) as page", [offset, limit])).rows[0].page;
    let hot = await popular();
    assert.equal(hot.windowDays, 7);
    assert.equal(hot.items[0].totalTraders, 2);
    assert.equal(hot.items[0].shortTraders, 2);
    assert.equal(hot.items[0].longTraders, 0);
    assert.deepEqual(Object.keys(hot.items[0]).sort(), ["longTraders", "opinion", "shortTraders", "totalTraders"]);
    const second = await insert(a, .1, fill);
    await db.query("update public.bsmart_feed_orders set opinion_id=$2 where id=$1", [second, crypto.randomUUID()]);
    hot = await popular(0, 1);
    assert.equal(hot.items[0].totalTraders, 2); assert.equal(hot.nextOffset, 1);
    assert.equal((await popular(1, 1)).items[0].totalTraders, 1);
    await db.query("update public.bsmart_feed_orders set last_filled_at=now()-interval '8 days' where id=$1", [other]);
    assert.ok((await popular()).items.every((item: any) => item.totalTraders === 1));
    assert.equal((await people()).totalTraders, 2, "Detail counts remain all-time");
    assert.equal((await people()).totalNotionalUSD, "48", "Trade value remains all-time");
    const claim = await db.query<any>("select * from public.bsmart_feed_claim($1,null,1)", [a]);
    assert.equal(claim.rows[0].id, pending);
    assert.equal((await db.query("select * from public.bsmart_feed_claim(null,null,5)")).rows.length, 0);
    await db.exec("reset role");
    await db.exec(await Deno.readTextFile(new URL("202609120006_public_activity.sql", root)));
    assert.equal((await people()).publicTraders, 2, "Existing accounts become public after migration");
    await db.query("update public.bsmart_feed_profiles set visible=false,feed_visible=false where account_id=$1", [a]);
    assert.equal((await people()).publicTraders, 2, "Old clients cannot hide activity");
    assert.ok((await feed()).items.length > 0);
    const c = crypto.randomUUID();
    await db.query("insert into auth.users values ($1)", [c]);
    assert.equal((await db.query<any>("select * from public.bsmart_feed_profiles where account_id=$1", [c])).rows.length, 1);
    const created = (await db.query<any>("select * from public.bsmart_feed_profiles where account_id=$1", [c])).rows[0];
    assert.equal(created.visible, true); assert.equal(created.feed_visible, true);
    await db.query("update public.bsmart_feed_profiles set avatar_url='storage:old.jpg' where account_id=$1", [c]);
    await db.query("update public.bsmart_feed_profiles set avatar_url='storage:new.jpg' where account_id=$1", [c]);
    await db.query("delete from auth.users where id=$1", [c]);
    assert.equal((await db.query("select * from public.bsmart_profile_avatar_cleanup")).rows.length, 2);
    await db.exec("reset role; set role authenticated");
    await assert.rejects(() => db.query("select * from public.bsmart_feed_claim(null,null,5)"));
    await assert.rejects(() => db.query("select * from public.bsmart_feed_orders"));
    await assert.rejects(() => db.query("select public.bsmart_feed_page(0,10,null)"));
    await assert.rejects(() => db.query("select public.bsmart_opinion_traders($1,0,30)", [opinion]));
    await assert.rejects(() => db.query("select public.bsmart_feed_popular(0,10)"));
  } finally { await db.close(); }
});
