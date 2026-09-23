import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { handle } from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !key) throw new Error("Supabase runtime configuration missing");
const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
Deno.serve(req => handle(req, client, {
  depositsEnabled: Deno.env.get("BSMART_DEPOSITS_ENABLED") === "true",
  tradingEnabled: Deno.env.get("BSMART_TRADING_ENABLED") === "true",
  withdrawalsEnabled: false,
  acrossWithdrawalsEnabled: Deno.env.get("BSMART_ACROSS_WITHDRAWALS_ENABLED") === "true",
}));
