import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { type InfoReader, verifyExecution } from "./verification.ts";
import { cleanupAvatars } from "../bsmart-profile/avatars.ts";

type RPCResult = { data: any; error: any; status?: number };

export async function retryQueueRPC(run: () => PromiseLike<RPCResult>,
  pause: () => Promise<void> = () => new Promise(resolve => setTimeout(resolve, 400))) {
  const first = await run();
  if (!first.error || ![0, 408, 429, 502, 503, 504].includes(first.status ?? -1)) return first;
  // A lost claim response may already hold a lease; it expires without publishing a fill.
  await pause();
  return await run();
}

export async function reconcile(client: SupabaseClient, info: InfoReader,
  account: string | null, cloid: string | null, limit: number, now: number) {
  const { data: orders, error, status } = await retryQueueRPC(() => client.rpc("bsmart_feed_claim", {
    p_account: account, p_cloid: cloid, p_limit: limit,
  }));
  if (error || !Array.isArray(orders)) {
    console.error("feed_claim_failed", JSON.stringify({ status, code: error?.code,
      hasError: !!error, resultType: orders === null ? "null" : typeof orders,
      transport: error?.message?.includes("fetch failed") || error?.message?.includes("FetchError") }));
    throw new Error("database_unavailable");
  }
  let verified = 0, failed = 0;
  for (const order of orders) {
    try {
      const execution = await verifyExecution(order, info, now);
      const values = execution ? { execution, executed_at: execution.executedAt,
        last_filled_at: execution.lastFilledAt, verification_state: "verified" } : {
        next_check_at: new Date(now + Math.min(300000, 5000 * 2 ** Math.min(order.verification_attempts, 6))).toISOString(),
      };
      const saved = await client.from("bsmart_feed_orders").update(values).eq("id", order.id)
        .eq("account_id", order.account_id).eq("checked_at", order.checked_at).is("execution", null);
      if (saved.error) throw new Error("database_unavailable");
      if (execution) verified += 1;
    } catch { failed += 1; }
  }
  return { checked: orders.length, verified, failed };
}

export async function handleWorker(req: Request, client: SupabaseClient, info: InfoReader) {
  const headers = { "Cache-Control": "no-store" };
  const token = (req.headers.get("authorization") ?? "").match(/^Bearer ([0-9a-f]{64})$/)?.[1];
  if (!token || req.method !== "POST") return Response.json({ error: "unauthorized" }, { status: 401, headers });
  try {
    const auth = await retryQueueRPC(() => client.rpc("bsmart_feed_worker_authorized", { p_token: token }));
    if (auth.error) throw new Error("database_unavailable");
    if (auth.data !== true) return Response.json({ error: "unauthorized" }, { status: 401, headers });
    const result = await reconcile(client, info, null, null, 5, Date.now());
    const heartbeat = await client.storage.from("bsmart-feed-catalog").upload("worker-status.json",
      JSON.stringify({ ...result, checkedAt: new Date().toISOString() }),
      { contentType: "application/json", upsert: true, cacheControl: "0" });
    if (heartbeat.error) throw new Error("heartbeat_unavailable");
    try { await cleanupAvatars(client); } catch { console.error("avatar_cleanup_unavailable"); }
    return Response.json(result, { headers });
  } catch (error) {
    const reason = error instanceof Error &&
        ["database_unavailable", "heartbeat_unavailable"].includes(error.message)
      ? error.message : "reconcile_unavailable";
    console.error("feed_worker_failed", reason);
    return Response.json({ error: reason }, { status: 503, headers });
  }
}
