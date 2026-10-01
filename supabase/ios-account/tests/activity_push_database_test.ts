import { strict as assert } from "node:assert";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";

Deno.test("immediate activity SQL selects top two followed actors and independently publishes verified native events", async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create table auth.users(id uuid primary key);
      create schema cron; create function cron.schedule(text,text,text) returns bigint language sql as $$ select 1::bigint $$;
      create function public.bsmart_push_run_worker() returns bigint language sql as $$ select 1::bigint $$;
      create table public.test_clock(at timestamptz); insert into public.test_clock values('2026-10-01T10:01:00Z');
      create function public.test_now() returns timestamptz language sql as $$ select at from public.test_clock $$;
      create table public.bsmart_push_devices(id uuid primary key, user_id uuid references auth.users,
        enabled boolean default true,environment text default 'production',notify_authors boolean default true,
        updated_at timestamptz default public.test_now(),apns_token text default repeat('a',64),locale text default 'zh-Hans',
        followed_author_ids text[] default '{}');
      create table public.bsmart_content_releases(revision text primary key,provenance jsonb,created_at timestamptz);
      create table public.bsmart_content_active(channel text primary key,revision text);
      create table public.bsmart_content_pages(revision text,collection text,payload jsonb);
      create table public.bsmart_subject_activity_snapshots(channel text primary key,payload jsonb);
      create table public.bsmart_feed_profiles(account_id uuid primary key,public_id uuid,nickname text,
        visible boolean,feed_visible boolean);
      create table public.bsmart_social_follows(follower_id uuid,followed_id uuid,primary key(follower_id,followed_id));
      create table public.bsmart_feed_orders(id uuid primary key,account_id uuid,intent jsonb,execution jsonb,executed_at timestamptz);
      create table public.bsmart_trade_theses(trade_id uuid primary key,body text,published_at timestamptz);
      insert into public.bsmart_subject_activity_snapshots values('production','{"subjects":[],"events":[{"id":"baseline"}]}');`);
    const source = await Deno.readTextFile(new URL("../supabase/migrations/202610010002_immediate_activity_push.sql", import.meta.url));
    await db.exec(source.replaceAll("now()", "public.test_now()"));
    const repair = await Deno.readTextFile(new URL("../supabase/migrations/202610010003_activity_push_compatibility.sql", import.meta.url));
    await db.exec(repair.replaceAll("now()", "public.test_now()"));
    await db.exec(repair.replaceAll("now()", "public.test_now()"));
    await db.exec((await Deno.readTextFile(new URL("../supabase/migrations/202610010004_native_social_push_follow.sql", import.meta.url)))
      .replaceAll("now()", "public.test_now()"));
    const scalar = async <T = any>(sql: string, params: unknown[] = []) =>
      (await db.query<{ value: T }>(`select ${sql} as value`, params)).rows[0].value;
    const user = crypto.randomUUID(), device = crypto.randomUUID(), sandboxUser = crypto.randomUUID();
    const native = crypto.randomUUID(), account = crypto.randomUUID();
    await db.query("insert into auth.users values($1),($2)", [user, sandboxUser]);
    await db.query(`insert into public.bsmart_push_devices(id,user_id,followed_author_ids)
      values($1,$2,array['a','b','c','missing','bsmart:'||$3])`, [device, user, native]);
    await db.query(`insert into public.bsmart_push_devices(id,user_id,environment,followed_author_ids)
      values($1,$2,'development',array['a','b','c'])`, [crypto.randomUUID(), sandboxUser]);
    const event = (id: string, actor: string, score: number | null = 0, kind = "subject") => ({
      event_kind: kind, event_id: id, actor_id: actor, actor_name: actor, ticker: "AAPL", body: "Original text",
      follow_return: score, published_at: "2026-10-01T10:00:00Z",
    });
    const enqueue = (id: string, events: unknown[]) => scalar<number>("public.bsmart_activity_push_enqueue($1,$2::jsonb)", [id, JSON.stringify(events)]);
    assert.equal(await enqueue("disabled", [event("disabled", "a")]), 0);
    await scalar("public.bsmart_activity_push_configure(true)");
    assert.equal(await enqueue("disabled-replay", [event("disabled", "a")]), 0);
    assert.equal(await enqueue("baseline-replay", [event("baseline", "a")]), 0);
    assert.equal(await enqueue("ranked", [event("a1", "a", .2), event("b1", "b", .8), event("c1", "c", -.1),
      event("unknown", "missing", null), event("unfollowed", "other", 100),
      { ...event("new-b", "b", .8), published_at: "2026-10-01T10:00:30Z" }]), 2);
    assert.deepEqual((await db.query<any>("select event_id from public.bsmart_activity_push_outbox order by follow_return desc")).rows
      .map(r => r.event_id), ["new-b", "a1"]);
    assert.equal(await enqueue("replay", [event("c1", "c", 1000)]), 0, "Unselected events cannot replay after rescore");
    assert.equal(await scalar("(select count(*)::integer from public.bsmart_activity_push_outbox where user_id=$1)", [sandboxUser]), 0);
    const d = await scalar("public.bsmart_activity_push_claim()");
    assert.equal(d.item_count, 1); assert.ok(d.notice.body); assert.equal(d.environment, "production");
    const finish = (delivery: any, status: number | null, invalid = false) => scalar(
      "public.bsmart_activity_push_complete($1,$2,$3,$4)", [delivery.notice.id, delivery.apns_id, status, invalid]);
    assert.equal(await finish(d, 200), true); assert.equal(await finish(d, 200), false);
    const second = await scalar("public.bsmart_activity_push_claim()");
    assert.equal(await scalar("public.bsmart_activity_push_claim()"), null, "Sending claims are never reclaimed");
    await db.exec("update public.test_clock set at=at+interval '1 minute'");
    await db.query("update public.bsmart_push_devices set updated_at=public.test_now() where id=$1", [device]);
    assert.equal(await finish(second, 410, true), true);
    assert.equal(await scalar("(select enabled from public.bsmart_push_devices where id=$1)", [device]), true);

    await db.query("insert into public.bsmart_feed_profiles values($1,$2,'Trader',true,true)", [account, native]);
    const order = crypto.randomUUID();
    const intent = { ticker: "AAPL", reduceOnly: false, notionalUSD: "999" };
    const execution = { side: "long", notionalUSD: "100.00" };
    await db.query("insert into public.bsmart_feed_orders values($1,$2,$3,null,null)", [order, account, intent]);
    assert.equal(await scalar("(select count(*)::integer from public.bsmart_activity_push_outbox where event_kind='native_trade')"), 0);
    await db.query("update public.bsmart_feed_orders set execution=$2,executed_at=public.test_now() where id=$1", [order, execution]);
    await db.query("update public.bsmart_feed_orders set execution=$2 where id=$1", [order, { ...execution, notionalUSD: "120" }]);
    await db.query("insert into public.bsmart_trade_theses values($1,'User thesis',public.test_now())", [order]);
    const nativeRows = (await db.query<any>("select event_kind,body from public.bsmart_activity_push_outbox where event_kind like 'native_%' order by event_kind")).rows;
    assert.equal(nativeRows.length, 2);
    assert.equal(nativeRows[0].body, "做多了$120的$AAPL仓位");
    assert.equal(nativeRows[1].body, "做多了$100的$AAPL仓位");
    assert.equal(await scalar("public.bsmart_activity_push_trade_body($1,$2)", [{ ticker: "AAPL", reduceOnly: true }, execution]), "平空了$100的$AAPL仓位");
    assert.equal(await scalar("public.bsmart_activity_push_trade_body($1,$2)", [{ ticker: "AAPL" }, { side: "short", notionalUSD: "0" }]), null);
    await db.query("update public.bsmart_feed_profiles set visible=false where account_id=$1", [account]);
    assert.equal(await scalar("public.bsmart_activity_push_claim()"), null, "Privacy is checked again before sending");
    await db.query("update public.bsmart_feed_profiles set visible=true where account_id=$1", [account]);
    assert.equal(await enqueue("native-independent", Array.from({ length: 4 }, (_, i) => event("native" + i, "bsmart:" + native, null, "native_trade"))), 4);
    await db.query("update public.bsmart_push_devices set followed_author_ids='{}' where id=$1", [device]);
    assert.equal(await scalar("public.bsmart_activity_push_claim()"), null, "Unfollow cancels pending notices");
    await db.query("update public.bsmart_push_devices set followed_author_ids=array['a','b','c','missing'] where id=$1", [device]);
    await db.query("insert into public.bsmart_social_follows values($1,$2)", [user, account]);
    assert.equal(await enqueue("social-follow", [event("social-follow", "bsmart:" + native, null, "native_trade")]), 1);
    await db.query("delete from public.bsmart_social_follows where follower_id=$1", [user]);
    assert.equal(await scalar("public.bsmart_activity_push_claim()"), null, "Native social unfollow cancels the pending operation");
    assert.equal(await enqueue("consent", [event("consent", "a")]), 1);
    await db.query("insert into public.bsmart_push_devices(id,user_id,updated_at) values($1,$2,public.test_now()+interval '1 second')", [crypto.randomUUID(), user]);
    assert.equal(await scalar("public.bsmart_activity_push_claim()"), null, "A stale device cannot override the latest follows");
    await db.query("delete from public.bsmart_push_devices where user_id=$1 and id<>$2", [user, device]);
    assert.equal(await enqueue("expires", [event("expires", "a")]), 1);
    await db.exec("update public.test_clock set at=at+interval '25 hours'");
    assert.equal(await scalar("public.bsmart_activity_push_claim()"), null);

    // Immutable publication activation, not page writes or price/Score edits, is the boundary.
    const update = (id: string) => ({ id, authorId: "a", authorName: "Author", platform: "x", ticker: "AAPL",
      originalText: "Raw opinion", publishedAt: "2026-10-01T10:00:00Z", sourcePostId: id });
    for (const [revision, kind, id, created] of [["old", "baseline", "old-post", "2026-10-01"],
      ["new", "daily-x", "new-post", "2026-10-02"], ["prices", "price-refresh", "price-post", "2026-10-03"]]) {
      await db.query("insert into public.bsmart_content_releases values($1,$2,$3)", [revision, { kind }, created]);
      await db.query("insert into public.bsmart_content_pages values($1,'smart-account-updates',$2)",
        [revision, { revision, page: 0, pages: 1, total: 1, items: [update(id)] }]);
    }
    await db.exec("insert into public.bsmart_content_active values('production','old'); update public.bsmart_content_active set revision='new'");
    assert.equal(await scalar("(select count(*)::integer from public.bsmart_activity_push_outbox where publication='new')"), 1);
    await db.exec("update public.bsmart_content_active set revision='prices'; update public.bsmart_content_active set revision='old'");
    assert.equal(await scalar("(select count(*)::integer from public.bsmart_activity_push_outbox where publication in ('prices','old'))"), 0);
    const subject = { id: "b", name: "Politician", research: { meanOpenReturn: .7 } };
    const snapshot = { subjects: [subject], events: [{ id: "trade-new", subjectID: "b", ticker: "AAPL", action: "sell", amountRange: "$1,001 - $15,000", displayDay: "2026-10-01" }] };
    await db.query("update public.bsmart_subject_activity_snapshots set payload=$1", [snapshot]);
    assert.equal(await scalar("(select body from public.bsmart_activity_push_outbox where event_id='trade-new')"), "sell · $1,001 - $15,000");
    await db.query("update public.bsmart_subject_activity_snapshots set payload=$1", [{ ...snapshot, subjects: [{ ...subject, research: { meanOpenReturn: .9 } }] }]);
    assert.equal(await scalar("(select count(*)::integer from public.bsmart_activity_push_outbox where event_id='trade-new')"), 1);
    for (const role of ["anon", "authenticated"]) {
      await db.exec(`set role ${role}`);
      for (const sql of ["select * from public.bsmart_activity_push_outbox", "select public.bsmart_activity_push_claim()",
        "select public.bsmart_activity_push_configure(true)", "select public.bsmart_activity_push_enqueue('x','[]')"]) {
        await assert.rejects(() => db.query(sql));
      }
      await db.exec("reset role");
    }
  } finally { await db.close(); }
});
