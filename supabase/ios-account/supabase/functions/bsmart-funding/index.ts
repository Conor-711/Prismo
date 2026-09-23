import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { handle } from "./handler.ts";

const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
Deno.serve(req => handle(req, client, {
  enabled: Deno.env.get("BSMART_DEPOSITS_ENABLED") === "true" &&
    Deno.env.get("BSMART_RELAY_FUNDING_ENABLED") === "true",
  relayKey: Deno.env.get("BSMART_RELAY_API_KEY") ?? "",
}));
