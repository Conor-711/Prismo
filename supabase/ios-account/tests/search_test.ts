import { handleSearch, profileSearchFilter } from "../supabase/functions/bsmart-search/handler.ts";

function assert(value: unknown, message = "assertion failed"): asserts value { if (!value) throw Error(message); }
const headers = { Authorization: "Bearer a.b.c" };
const req = (query = "", method = "GET") => new Request("https://test.invalid/bsmart-search/profiles?" + query, { headers, method });
function mock(rows: any[] = []) {
  const calls: any[] = [];
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: "private-auth-id", identities: [{ provider: "google" }] } } }) },
    from: (table: string) => {
      calls.push(["from", table]);
      const query: any = {};
      for (const method of ["select", "eq", "gt", "or", "order", "range"]) {
        query[method] = (...args: any[]) => { calls.push([method, ...args]); return query; };
      }
      query.then = (resolve: any) => Promise.resolve({ data: rows }).then(resolve);
      return query;
    },
  };
  return { client, calls };
}

Deno.test("search requires a non-anonymous Google or Apple account before reading profiles", async () => {
  const { client, calls } = mock();
  assert((await handleSearch(new Request("https://test.invalid/bsmart-search/profiles"), client)).status === 401);
  client.auth.getUser = async () => ({ data: { user: { is_anonymous: true, identities: [{ provider: "google" }] } } });
  assert((await handleSearch(req(), client)).status === 401);
  client.auth.getUser = async () => ({ data: { user: null }, error: { status: 401 } });
  assert((await handleSearch(req(), client)).status === 401);
  assert(calls.length === 0);
});

Deno.test("temporary Auth errors cannot trigger client sign-out", async () => {
  const { client, calls } = mock();
  for (const status of [0, 429, 500, 502, 503]) {
    client.auth.getUser = async () => ({ data: { user: null }, error: { status } });
    assert((await handleSearch(req("q=BTC"), client)).status === 503);
  }
  assert(calls.length === 0);
});

Deno.test("search exposes only completed public profile fields and resolves pagination", async () => {
  const rows = [0, 1, 2].map(i => ({ public_id: crypto.randomUUID(), nickname: "BTC " + i,
    handle: "btc_" + i, avatar_url: null, account_id: "secret-id", email: "private@example.invalid", wallet: "private-wallet" }));
  const { client, calls } = mock(rows);
  const response = await handleSearch(req("q=BTC&limit=2&offset=4"), client);
  const body = await response.json();
  assert(response.status === 200 && response.headers.get("cache-control") === "no-store");
  assert(body.items.length === 2 && body.nextOffset === 6);
  assert(Object.keys(body.items[0]).sort().join() === "avatarURL,handle,id,nickname");
  assert(calls.some(c => c.join() === "select,public_id,nickname,handle,avatar_url"));
  assert(calls.some(c => c.join() === "eq,visible,true"));
  assert(calls.some(c => c.join() === "eq,feed_visible,true"));
  assert(calls.some(c => c.join() === "gt,revision,0"));
  assert(calls.some(c => c.join() === "range,4,6"));
  assert(calls.filter(c => c[0] === "order").map(c => c[1]).join() === "nickname,public_id");
});

Deno.test("empty query offers community overview and empty results are not errors", async () => {
  const { client, calls } = mock();
  const response = await handleSearch(req(), client);
  assert(response.status === 200);
  assert(JSON.stringify(await response.json()) === '{"items":[],"nextOffset":null}');
  assert(!calls.some(c => c[0] === "or"));
  assert(calls.some(c => c[0] === "order" && c[1] === "updated_at" && c[2].ascending === false));
});

Deno.test("LIKE wildcards and PostgREST syntax are treated as literal user input", async () => {
  for (const q of ["btc_", "100%", 'btc\",visible.eq.false,nickname.ilike.\"', "a\\b", "比特币"]) {
    const filter = profileSearchFilter(q);
    const expectedLiteral = JSON.stringify("%" + q.replace(/[\\%_]/g, "\\$&") + "%");
    assert(filter === `nickname.ilike.${expectedLiteral},handle.ilike.${expectedLiteral}`);
    const { client, calls } = mock();
    assert((await handleSearch(req(new URLSearchParams({ q }).toString()), client)).status === 200);
    assert(calls.find(c => c[0] === "or")[1] === filter);
  }
});

Deno.test("normalizes handle prefixes and rejects invalid bounds without database reads", async () => {
  const { client, calls } = mock();
  for (const query of ["limit=21", "offset=-1", "offset=10001", "limit=NaN", "offset=1.2", "q=%00", "q=" + "x".repeat(81)]) {
    assert((await handleSearch(req(query), client)).status === 422);
  }
  assert((await handleSearch(req("", "POST"), client)).status === 404);
  assert(calls.length === 0);
  assert((await handleSearch(req("q=%40BTC"), client)).status === 200);
  assert(calls.find(c => c[0] === "or")[1] === profileSearchFilter("BTC"));
});

Deno.test("database failures stay unavailable and cannot leak diagnostics", async () => {
  const { client } = mock();
  client.from = () => { throw Error("private connection details"); };
  const response = await handleSearch(req("q=BTC"), client);
  assert(response.status === 503 && !(await response.text()).includes("private connection"));
});
