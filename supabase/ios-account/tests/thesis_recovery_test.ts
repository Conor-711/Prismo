import { strict as assert } from "node:assert";
import { reconcile } from "../supabase/functions/bsmart-feed/reconcile.ts";

const now = Date.parse("2026-10-01T11:22:00Z");
function fixture(attempts = 1) {
  const order = { id: crypto.randomUUID(), account_id: crypto.randomUUID(),
    wallet: "0x" + "1".repeat(40), checked_at: new Date(now).toISOString(),
    registered_at: new Date(now - 1000).toISOString(), verification_attempts: attempts,
    intent: { cloid: "0x" + "2".repeat(32), coin: "xyz:CRWD", side: "sell" } };
  const writes: { values: Record<string, unknown>; filters: Record<string, unknown> }[] = [];
  const client: any = { rpc: async () => ({ data: [order], error: null }), from: (table: string) => {
    assert.equal(table, "bsmart_feed_orders");
    return { update: (values: Record<string, unknown>) => {
      const filters: Record<string, unknown> = {};
      const builder: any = { eq: (key: string, value: unknown) => { filters[key] = value; return builder; },
        is: (key: string, value: unknown) => { filters[key] = value; return builder; },
        then: (resolve: (value: unknown) => unknown) => {
          writes.push({ values, filters }); return Promise.resolve(resolve({ error: null }));
        } };
      return builder;
    } };
  } };
  return { order, client, writes };
}

Deno.test("failed thesis verification releases only its own claim with backoff, never a fill", async () => {
  for (const [attempts, delay] of [[1, 10000], [2, 20000], [20, 300000]]) {
    const { order, client, writes } = fixture(attempts);
    let reads = 0;
    const result = await reconcile(client, async (body) => {
      reads++; assert.equal(body.type, "orderStatus"); assert.equal(body.oid, order.intent.cloid);
      throw Error("upstream_unavailable");
    }, order.account_id, order.intent.cloid, 1, now);
    assert.deepEqual(result, { checked: 1, verified: 0, failed: 1 });
    assert.equal(reads, 1);
    assert.deepEqual(writes, [{ values: { next_check_at: new Date(now + delay).toISOString() },
      filters: { id: order.id, account_id: order.account_id, checked_at: order.checked_at, execution: null } }]);
  }
});

Deno.test("unknown order remains pending rather than becoming an eligible thesis", async () => {
  const { order, client, writes } = fixture();
  const result = await reconcile(client, async () => ({ status: "unknownOid" }),
    order.account_id, order.intent.cloid, 1, now);
  assert.deepEqual(result, { checked: 1, verified: 0, failed: 0 });
  assert.deepEqual(Object.keys(writes[0].values), ["next_check_at"]);
  assert.equal(writes[0].filters.execution, null);
});

Deno.test("mismatched exchange evidence cannot authorize publishing", async () => {
  const { order, client, writes } = fixture();
  const result = await reconcile(client, async () => ({ status: "order", order: { order: {} } }),
    order.account_id, order.intent.cloid, 1, now);
  assert.deepEqual(result, { checked: 1, verified: 0, failed: 1 });
  assert.deepEqual(Object.keys(writes[0].values), ["next_check_at"]);
});
