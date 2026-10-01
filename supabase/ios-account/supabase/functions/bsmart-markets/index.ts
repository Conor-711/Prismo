import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { handleMarkets } from "./handler.ts";
import { providers } from "./providers.ts";

const url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !key) throw new Error("Supabase runtime configuration missing");
const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
const catalogs = providers();
Deno.serve(req => handleMarkets(req, client, {
  catalogs, previewsEnabled: Deno.env.get("BSMART_XSTOCKS_PREVIEW_ENABLED") === "true",
  apiKey: Deno.env.get("BSMART_JUPITER_API_KEY"),
}));
