import { strict as assert } from "node:assert";
import { storageCatalog } from "../supabase/functions/bsmart-feed/catalog.ts";
import { handleWorker, reconcile, retryQueueRPC } from "../supabase/functions/bsmart-feed/reconcile.ts";

Deno.test("private catalog resolves immutable release and rejects identity mismatch", async () => {
  const id = crypto.randomUUID(), requests: string[] = [];
  const client: any = { storage: { from: (bucket: string) => {
    assert.equal(bucket, "bsmart-feed-catalog");
    return { download: async (path: string) => {
      requests.push(path);
      const value = path === "active.json" ? { schema: 1, release: "a".repeat(64) } : { id, authorId: "author" };
      return { data: new Blob([JSON.stringify(value)]) };
    } };
  } } };
  const catalog = storageCatalog(client);
  assert.equal((await catalog(id, "author")).id, id);
  assert.deepEqual(requests, ["active.json", "a".repeat(64) + "/" + id + ".json"]);
  assert.equal((await catalog(id, "author")).id, id);
  assert.equal(requests.length, 2);
  await assert.rejects(() => catalog(id, "imposter"));
  await assert.rejects(() => catalog("../active", "author"));
});

Deno.test("missing opinion is distinct from a storage outage", async () => {
  for (const [statusCode, expected] of [["404", "opinion_unavailable"], ["503", "catalog_unavailable"]]) {
    const client: any = { storage: { from: () => ({ download: async (path: string) => path === "active.json"
      ? { data: new Blob([JSON.stringify({ schema: 1, release: "a".repeat(64) })]) }
      : { error: { statusCode } } }) } };
    await assert.rejects(() => storageCatalog(client)(crypto.randomUUID(), "author"), new RegExp(expected));
  }
});

Deno.test("worker refuses client JWT and invalid scheduler token before claiming orders", async () => {
  let calls = 0;
  const client: any = { rpc: async (name: string) => {
    calls++; assert.equal(name, "bsmart_feed_worker_authorized"); return { data: false };
  } };
  const info = async () => { throw Error("must not read exchange"); };
  for (const token of ["", "Bearer abc.def.ghi", "Bearer " + "a".repeat(64)]) {
    const result = await handleWorker(new Request("https://test/reconcile", { method: "POST", headers: { Authorization: token } }), client, info);
    assert.equal(result.status, 401);
  }
  assert.equal(calls, 1);
});

Deno.test("sync claims only caller's scope and empty queue does not query exchange", async () => {
  const account = crypto.randomUUID();
  const client: any = { rpc: async (name: string, args: any) => {
    assert.equal(name, "bsmart_feed_claim");
    assert.deepEqual(args, { p_account: account, p_cloid: null, p_limit: 1 });
    return { data: [] };
  } };
  assert.deepEqual(await reconcile(client, async () => { throw Error("unexpected read"); }, account, null, 1, Date.now()),
    { checked: 0, verified: 0, failed: 0 });
});

Deno.test("authorized scheduler drains bounded queue and records private heartbeat", async () => {
  let wrote = false;
  const client: any = {
    rpc: async (name: string, args: any) => {
      if (name === "bsmart_feed_worker_authorized") return { data: true };
      assert.equal(name, "bsmart_feed_claim");
      assert.deepEqual(args, { p_account: null, p_cloid: null, p_limit: 5 });
      return { data: [] };
    },
    storage: { from: (bucket: string) => ({ upload: async (path: string, value: string) => {
      assert.equal(bucket, "bsmart-feed-catalog"); assert.equal(path, "worker-status.json");
      const data = JSON.parse(value); assert.equal(data.failed, 0); assert.equal(data.checked, 0);
      assert.ok(data.checkedAt); wrote = true; return {};
    } }) },
  };
  const response = await handleWorker(new Request("https://test/reconcile", {
    method: "POST", headers: { Authorization: "Bearer " + "a".repeat(64) },
  }), client, async () => { throw Error("empty queue"); });
  assert.equal(response.status, 200); assert.equal(wrote, true);
});

Deno.test("queue RPC retries a transient gateway failure once, never permanent denial", async () => {
  for (const status of [0, 408, 429, 502, 503, 504, 401, 403, 400]) {
    let calls = 0, pauses = 0;
    const result = await retryQueueRPC(async () => {
      calls++;
      return calls === 1 ? { data: null, error: {}, status } : { data: [], error: null, status: 200 };
    }, async () => { pauses++; });
    const transient = [0, 408, 429, 502, 503, 504].includes(status);
    assert.equal(calls, transient ? 2 : 1); assert.equal(pauses, transient ? 1 : 0);
    assert.equal(result.status, transient ? 200 : status);
  }
  let calls = 0;
  await retryQueueRPC(async () => { calls++; return { data: null, error: {}, status: 504 }; }, async () => {});
  assert.equal(calls, 2);
});

Deno.test("worker reports unavailable database separately from rejected scheduler identity", async () => {
  const client: any = { rpc: async () => ({ data: null, error: { code: "42501" }, status: 403 }) };
  const result = await handleWorker(new Request("https://test/reconcile", {
    method: "POST", headers: { Authorization: "Bearer " + "a".repeat(64) },
  }), client, async () => { throw Error("must not query exchange"); });
  assert.equal(result.status, 503);
  assert.equal((await result.json()).error, "database_unavailable");
});
