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
    rpc(name: string, args: { p_subject_id: string | null }) {
      calls.push(["rpc", name, args.p_subject_id]);
      const payload = (rows.bsmart_subject_activity_snapshots as { payload?: any } | undefined)?.payload;
      if (!payload) return Promise.resolve({ data: null });
      const cutoff = new Date(Date.now() - 400 * 86_400_000).toISOString().slice(0, 10);
      return Promise.resolve({ data: { ...payload,
        subjects: args.p_subject_id ? payload.subjects.filter((item: any) => item.id === args.p_subject_id) : payload.subjects,
        events: payload.events.filter((item: any) => args.p_subject_id
          ? item.subjectID === args.p_subject_id : item.displayDay >= cutoff) } });
    },
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
  assert(calls.filter(c => c.join() === "from,bsmart_content_releases").length === 1);
});
Deno.test("subject activity requires authentication and returns the current snapshot", async () => {
  const { client, calls, rows } = mock();
  const payload = { schemaVersion: 1, subjects: [{ id: "celebrity:sample" }], events: [] };
  rows.bsmart_subject_activity_snapshots = { payload };
  assert((await handleContent(new Request("https://test.invalid/bsmart-content/subject-activity"), client)).status === 401);
  const response = await handleContent(req("subject-activity"), client);
  assert(response.status === 200 && JSON.stringify(await response.json()) === JSON.stringify(payload));
  assert(calls.some(c => c.join() === "rpc,bsmart_subject_activity_read,"));
  delete rows.bsmart_subject_activity_snapshots;
  assert((await handleContent(req("subject-activity"), client)).status === 404);
});
Deno.test("subject activity keeps the home payload recent and serves full history by subject", async () => {
  const { client, rows } = mock();
  const today = new Date().toISOString().slice(0, 10);
  const payload = { schemaVersion: 1, subjects: [{ id: "celebrity:sample" }, { id: "institution:other" }],
    events: [{ id: "old", subjectID: "celebrity:sample", displayDay: "2023-10-01" },
      { id: "new", subjectID: "celebrity:sample", displayDay: today }] };
  rows.bsmart_subject_activity_snapshots = { payload };
  const recent = await (await handleContent(req("subject-activity"), client)).json();
  assert(recent.events.length === 1 && recent.events[0].id === "new");
  const history = await (await handleContent(req("subject-activity", "subjectID=celebrity%3Asample"), client)).json();
  assert(history.subjects.length === 1 && history.events.length === 2);
  assert((await handleContent(req("subject-activity", "subjectID=../invalid"), client)).status === 422);
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
