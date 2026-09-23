import { strict as assert } from "node:assert";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";
import { thesisInput } from "../supabase/functions/bsmart-feed/theses.ts";
import { handleFeed } from "../supabase/functions/bsmart-feed/handler.ts";

Deno.test("thesis input bounds Unicode, ignores no ownership fields and requires explicit like state", () => {
  assert.deepEqual(thesisInput({body: "  理由\n保留原文  "}, false), {p_body: "理由\n保留原文"});
  assert.equal((thesisInput({body: "😀".repeat(1000)}, false).p_body as string).length, 2000);
  for (const body of ["", " \n ", "x".repeat(1001), "bad\u0000text", "bad\u0085text"]) {
    assert.throws(() => thesisInput({body}, false));
  }
  for (const value of [{body:"ok", accountId:"spoof"}, {body:"ok", opinion:{}}, [], null]) {
    assert.throws(() => thesisInput(value, false));
  }
  for (const value of [{liked:1}, {liked:true, count:100}, {}]) assert.throws(() => thesisInput(value, true));
  assert.deepEqual(thesisInput({liked:false}, true), {p_liked:false});
});

Deno.test("thesis routes authenticate identity and pass only server-owned actor", async () => {
  const actor = crypto.randomUUID(), trade = crypto.randomUUID(), calls: any[] = [];
  const client: any = {auth: {getUser: async () => ({data:{user:{id:actor, identities:[{provider:"apple"}]}}})},
    rpc: (name: string, args: any) => {calls.push({name,args}); return {data:{id:trade}};}};
  const deps = {info: async () => ({}), catalog: async () => ({}), markets:{}};
  const req = (path: string, body?: any) => new Request("https://test.invalid/bsmart-feed"+path, {
    method: body ? "PUT" : "GET", headers:{Authorization:"Bearer a.b.c", "Content-Type":"application/json"},
    body:body ? JSON.stringify(body) : undefined});
  assert.equal((await handleFeed(req(`/trades/${trade}/thesis`, {body:"My reason"}),client,deps)).status,200);
  assert.deepEqual(calls[0], {name:"bsmart_thesis_publish",args:{p_actor:actor,p_trade:trade,p_body:"My reason"}});
  assert.equal((await handleFeed(req(`/trades/${trade}/thesis`, {body:"Reason",accountId:actor}),client,deps)).status,422);
  assert.equal(calls.length,1);
  assert.equal((await handleFeed(req("?mine=true"),client,deps)).status,422);
  await handleFeed(req("?includeTheses=true&mine=true"),client,deps);
  assert.equal(calls[1].args.p_mine,true); assert.equal(calls[1].args.p_actor,actor);
  assert.equal((await handleFeed(req(`?includeTheses=true&mine=true&profileId=${trade}`),client,deps)).status,422);
  client.rpc = () => ({data:{error:"thesis_exists"}});
  assert.equal((await handleFeed(req(`/trades/${trade}/thesis`,{body:"Changed"}),client,deps)).status,409);
  client.rpc = () => ({error:true});
  assert.equal((await handleFeed(req(`/theses/${trade}/like`,{liked:true}),client,deps)).status,503);
  client.auth.getUser = async () => ({data:{user:null},error:true});
  assert.equal((await handleFeed(req(`/theses/${trade}/like`,{liked:true}),client,deps)).status,401);
});

Deno.test("missing thesis migration is distinct from pending verification and other service failures", async () => {
  const actor = crypto.randomUUID(), trade = crypto.randomUUID();
  let result: any = {error:{code:"PGRST202"}};
  const client: any = {auth:{getUser:async()=>({data:{user:{id:actor,identities:[{provider:"apple"}]}}})},
    rpc:()=>result};
  const deps = {info:async()=>({}),catalog:async()=>({}),markets:{}};
  async function request(path: string, body?: any) {
    return await handleFeed(new Request("https://test.invalid/bsmart-feed"+path, {
      method:body ? "PUT":"GET", headers:{Authorization:"Bearer a.b.c","Content-Type":"application/json"},
      body:body ? JSON.stringify(body):undefined}),client,deps);
  }
  const path = "/orders/0x"+"1".repeat(32)+"/activity";
  for (const [route, body] of [[path,undefined],[`/trades/${trade}/thesis`,{body:"Reason"}],
      [`/theses/${trade}/like`,{liked:true}]] as const) {
    const response = await request(route,body);
    assert.equal(response.status,503);
    assert.deepEqual(await response.json(),{error:"thesis_not_ready"});
  }
  result = {data:{items:[]}};
  const pending = await request(path);
  assert.equal(pending.status,409);
  assert.deepEqual(await pending.json(),{error:"trade_pending"});
  result = {error:{code:"XX000"}};
  assert.deepEqual(await (await request(path)).json(),{error:"feed_unavailable"});
});

Deno.test("real SQL verifies owner and fill, persists one theory, deduplicates likes, projects both feeds and cascades deletion", async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create table auth.users(id uuid primary key);`);
    const root = new URL("../supabase/migrations/", import.meta.url);
    await db.exec(await Deno.readTextFile(new URL("202609120002_trade_feed.sql", root)));
    await db.exec("alter table public.bsmart_feed_profiles add column handle text;");
    await db.exec(await Deno.readTextFile(new URL("202609220004_trade_theses.sql", root)));
    const owner=crypto.randomUUID(), liker=crypto.randomUUID(), pending=crypto.randomUUID(), trade=crypto.randomUUID();
    await db.query("insert into auth.users values($1),($2)",[owner,liker]);
    await db.query("insert into public.bsmart_feed_profiles(account_id,nickname,visible,feed_visible) values($1,'Owner',true,true)",[owner]);
    for (const [id, execution] of [[pending,null],[trade,JSON.stringify({side:"long",notionalUSD:"12",marketCoin:"xyz:NVDA"})]]) {
      await db.query(`insert into public.bsmart_feed_orders(id,account_id,wallet,cloid,opinion_id,intent,opinion,execution,executed_at)
        values($1::uuid,$2,'private-wallet',$1::text,$3,'{}','{"platformPercentile":0.8}', $4,now())`,[id,owner,crypto.randomUUID(),execution]);
    }
    await db.exec("set role service_role");
    const publish = async (actor:string,id:string,body="Original reason") =>
      (await db.query<any>("select public.bsmart_thesis_publish($1,$2,$3) as result",[actor,id,body])).rows[0].result;
    const like = async (actor:string,liked:boolean) =>
      (await db.query<any>("select public.bsmart_thesis_like($1,$2,$3) as result",[actor,trade,liked])).rows[0].result;
    const page = async (actor=liker,mine=false,profile:string|null=null) =>
      (await db.query<any>("select public.bsmart_feed_social_page($1,0,10,$2,$3) as result",[actor,profile,mine])).rows[0].result;
    assert.equal((await publish(liker,trade)).error,"not_found");
    assert.equal((await publish(owner,pending)).error,"trade_pending");
    assert.equal((await publish(owner,trade," ")).error,"invalid_input");
    assert.equal((await publish(owner,trade,"bad\u0001text")).error,"invalid_input");
    assert.equal((await page()).items.length,0);
    assert.equal((await page(owner,true)).items[0].canPublishThesis,true);
    assert.equal((await page(liker,true)).items.length,0);
    const privateLookup = (await db.query<any>(
      "select public.bsmart_feed_social_page($1,0,1,null,false,$2) result",[liker,trade])).rows[0].result;
    assert.equal(privateLookup.items.length,0, "Knowing the order ID cannot retrieve another account's private write context");
    await db.query("update public.bsmart_feed_orders set opinion = opinion || '{\"sourceKind\":\"money\"}'::jsonb where id=$1",[trade]);
    assert.equal((await publish(owner,trade)).error,"invalid_input");
    assert.equal((await page(owner,true)).items.length,0);
    await db.query("update public.bsmart_feed_orders set opinion = opinion - 'sourceKind' where id=$1",[trade]);
    const first = await publish(owner,trade);
    assert.equal(first.body,"Original reason"); assert.equal(first.likeCount,0);
    assert.deepEqual(await publish(owner,trade),first);
    assert.equal((await publish(owner,trade,"Changed after market move")).error,"thesis_exists");
    assert.equal((await like(owner,true)).error,"own_thesis");
    assert.equal((await like(liker,true)).likeCount,1);
    assert.equal((await like(liker,true)).likeCount,1);
    assert.equal((await page()).items[0].thesis.likedByMe,true);
    assert.equal((await page()).items[0].canLikeThesis,true);
    assert.equal((await page(owner,true)).items[0].canLikeThesis,false);
    const profile=(await db.query<any>("select public_id from public.bsmart_feed_profiles")).rows[0].public_id;
    assert.deepEqual((await page(liker,false,profile)).items,(await page()).items);
    assert.equal(JSON.stringify(await page()).includes(owner),false);
    assert.equal(JSON.stringify(await page()).includes("private-wallet"),false);
    assert.equal((await like(liker,false)).likeCount,0);
    assert.equal((await like(liker,false)).likeCount,0);
    await like(liker,true);
    await db.exec("reset role; set role authenticated");
    await assert.rejects(()=>db.query("select * from public.bsmart_trade_theses"));
    await assert.rejects(()=>publish(owner,trade));
    await assert.rejects(()=>like(liker,false));
    await assert.rejects(()=>page());
    await db.exec("reset role");
    await db.query("delete from auth.users where id=$1",[liker]);
    assert.equal((await db.query<any>("select count(*)::int n from public.bsmart_trade_thesis_likes")).rows[0].n,0);
    await db.query("delete from auth.users where id=$1",[owner]);
    assert.equal((await db.query<any>("select count(*)::int n from public.bsmart_trade_theses")).rows[0].n,0);
  } finally {await db.close();}
});
