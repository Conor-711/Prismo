import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { apnsSender } from "./apns.ts";
import { activityPayload } from "./activity.ts";
import { Delivery, handlePush, Result } from "./handler.ts";

const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
  global: { fetch: (input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(8000) }) },
});
// APNs only accepts HTTP/2; disable HTTP/1 rather than relying on negotiation defaults.
const http = Deno.createHttpClient({ http1: false, http2: true });
const sender = apnsSender({ team: Deno.env.get("BSMART_APNS_TEAM_ID") ?? "",
  keyId: Deno.env.get("BSMART_APNS_KEY_ID") ?? "", topic: Deno.env.get("BSMART_APNS_TOPIC") ?? "",
  privateKey: Deno.env.get("BSMART_APNS_PRIVATE_KEY") ?? "" },
  (input, init) => fetch(input, { ...init, client: http }), Date.now, {
    exchange: async (identity, candidate) => await rpc("bsmart_push_provider_token", {
      p_identity: identity, p_token: candidate ?? null,
    }),
  }, activityPayload);
async function rpc(name: string, parameters = {}) {
  const { data, error } = await client.rpc(name, parameters);
  if (error) throw Error("database_unavailable");
  return data;
}
Deno.serve(req => handlePush(req, {
  authorized: async token => await rpc("bsmart_push_worker_authorized", { p_token: token }) === true,
  prepare: async () => {},
  claim: async () => await rpc("bsmart_activity_push_claim") as Delivery | null,
  continuePending: async () => { await rpc("bsmart_activity_push_continue"); },
  complete: async (delivery: Delivery, result: Result) => {
    if (await rpc("bsmart_activity_push_complete", { p_id: delivery.notice?.id,
      p_apns_id: delivery.apns_id, p_status: result.status, p_invalid: result.invalid }) !== true)
      throw Error("receipt_unavailable");
  },
}, sender, Deno.env.get("BSMART_CLOUD_PUSH_ENABLED") === "true"));
