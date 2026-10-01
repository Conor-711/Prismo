import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { apnsSender } from "../bsmart-push/apns.ts";
import type { Delivery } from "../bsmart-push/handler.ts";

const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const http = Deno.createHttpClient({ http1: false, http2: true });
let used = false;
Deno.serve(async req => {
  const reply = (status: number, value: unknown) => Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
  try {
    const config = JSON.parse(Deno.env.get("BSMART_APNS_PROBE_CONFIG") ?? "null");
    if (req.method !== "POST" || !config || !/^[a-f0-9]{64}$/.test(config.bearer) ||
      req.headers.get("authorization") !== "Bearer " + config.bearer) return reply(401, { error: "unauthorized" });
    if (used || !Number.isFinite(config.expires) || config.expires < Date.now() ||
      config.expires > Date.now() + 10 * 60_000 || config.delivery.environment !== "production") return reply(410, { error: "probe_expired" });
    // One operator request, one fixed server-side target; never parse a recipient from the request.
    used = true;
    const sender = apnsSender({ team: Deno.env.get("BSMART_APNS_TEAM_ID") ?? "",
      keyId: Deno.env.get("BSMART_APNS_KEY_ID") ?? "", topic: Deno.env.get("BSMART_APNS_TOPIC") ?? "",
      privateKey: Deno.env.get("BSMART_APNS_PRIVATE_KEY") ?? "" },
      (input, init) => fetch(input, { ...init, client: http }), Date.now, {
        exchange: async (identity, candidate) => {
          const { data, error } = await client.rpc("bsmart_push_provider_token", {
            p_identity: identity, p_token: candidate ?? null,
          });
          if (error) throw Error("provider_cache");
          return data;
        },
      }, () => ({ type: "content_update", aps: { alert: { title: "bSmart 推送测试",
        body: "APNs 已连接。点击查看通知。" }, sound: "default", "thread-id": "bsmart.push-test" } }));
    await sender.ready();
    const delivery: Delivery = { ...config.delivery, item_count: 1, slot_at: new Date().toISOString() };
    const result = await sender.send(delivery);
    return reply(200, { accepted: result.status === 200, providerStatus: result.status });
  } catch { return reply(503, { error: "probe_unavailable" }); }
});
