import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { handleFeed } from "./handler.ts";
import { boundedJSON } from "./verification.ts";
import { storageCatalog } from "./catalog.ts";
import { handleWorker } from "./reconcile.ts";

const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
const info = (body: Record<string, unknown>) => boundedJSON("https://api.hyperliquid.xyz/info", {
  method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
});
const catalog = storageCatalog(client);

Deno.serve(req => new URL(req.url).pathname.endsWith("/bsmart-feed/reconcile")
  ? handleWorker(req, client, info) : handleFeed(req, client, {
  info,
  catalog,
}));
