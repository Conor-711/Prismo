import { handleContent } from "../supabase/functions/bsmart-content/handler.ts";

function assert(value: unknown): asserts value { if (!value) throw Error("assertion failed"); }
const revision = "a".repeat(64);
const req = (path = "manifest", query = "", method = "GET") => new Request(
  "https://test.invalid/bsmart-content/" + path + "?" + query, { method, headers: { authorization: "Bearer a.b.c" } });
function mock() {
  const calls: unknown[][] = [];
  const rows: Record<string, unknown> = {
    bsmart_content_active: { revision }, bsmart_content_releases: { revision, manifest: { revision } },
    bsmart_content_pages: { payload: { revision, page: 0, pages: 1, total: 1, items: [{ id: "a" }] } },
  };
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { identities: [{ provider: "google" }] } } }) },
    from(table: string) {
      calls.push(["from", table]);
      const q: any = {};
      for (const m of ["select", "eq"]) q[m] = (...args: unknown[]) => { calls.push([m, ...args]); return q; };
      q.maybeSingle = () => Promise.resolve({ data: rows[table] ?? null });
      return q;
    },
  };
  return { client, calls, rows };
}
Deno.test("content verifies auth before every manifest/page read", async () => {
  const { client, calls } = mock();
  assert((await handleContent(new Request("https://test.invalid/bsmart-content/manifest"), client)).status === 401);
  client.auth.getUser = async () => ({ data: { user: { is_anonymous: true } } });
  assert((await handleContent(req(), client)).status === 401);
  client.auth.getUser = async () => ({ data: { user: null }, error: { status: 401 } });
  assert((await handleContent(req(), client)).status === 401);
  assert(calls.length === 0);
});
Deno.test("Auth outages remain retryable, not credential rejection", async () => {
  const { client, calls } = mock();
  for (const status of [429, 500, 503]) {
    client.auth.getUser = async () => ({ data: { user: null }, error: { status } });
    assert((await handleContent(req(), client)).status === 503);
  }
  assert(calls.length === 0);
});
Deno.test("reads immutable revision and never discloses provenance", async () => {
  const { client, calls } = mock();
  const response = await handleContent(req(), client);
  assert(response.headers.get("Cache-Control") === "no-store");
  assert(JSON.stringify(await response.json()) === JSON.stringify({ revision }));
  assert((await handleContent(req("page", `revision=${revision}&collection=smart-accounts`), client)).status === 200);
  assert(calls.some(c => c.join() === `eq,revision,${revision}`));
});
Deno.test("rejects unbounded queries and private collection names", async () => {
  const { client, calls } = mock();
  for (const query of [`revision=x&collection=smart-accounts`, `revision=${revision}&collection=wallets`,
    `revision=${revision}&collection=smart-accounts&page=-1`, `revision=${revision}&collection=smart-accounts&page=10001`,
    `revision=${revision}&collection=smart-accounts&owner=private`]) {
    assert((await handleContent(req("page", query), client)).status === 422);
  }
  assert((await handleContent(req("manifest", "", "POST"), client)).status === 405);
  assert(calls.length === 0);
});
Deno.test("missing evidence is empty, but missing release is never substituted", async () => {
  const { client, rows } = mock();
  delete rows.bsmart_content_pages;
  const query = `revision=${revision}&collection=smart-account-evidence&owner=x%3Aa`;
  const response = await handleContent(req("page", query), client);
  assert(response.status === 200 && (await response.json()).total === 0);
  assert((await handleContent(req("page", query + "&page=1"), client)).status === 404);
  delete rows.bsmart_content_releases;
  assert((await handleContent(req("page", query), client)).status === 404);
});
Deno.test("no baseline and database outages fail closed without leaking diagnostics", async () => {
  const { client, rows } = mock();
  delete rows.bsmart_content_active;
  assert((await handleContent(req(), client)).status === 503);
  client.from = () => { throw Error("database secret"); };
  const response = await handleContent(req(), client);
  assert(response.status === 503 && !(await response.text()).includes("secret"));
});
