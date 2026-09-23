import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { handleAcross, livePorts, reconcileAcross } from "./across_handler.ts";

const client = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  },
);
Deno.serve((req) => {
  const key = Deno.env.get("ACROSS_API_KEY");
  if (new URL(req.url).pathname.endsWith("/bsmart-withdrawals/reconcile")) {
    return key ? reconcileAcross(req, client, livePorts(key)) : Response.json({ error: "withdrawal_unavailable" }, { status: 503 });
  }
  return handleAcross(req, client, Deno.env.get("BSMART_ACROSS_WITHDRAWALS_ENABLED") === "true",
    key, Deno.env.get("ACROSS_INTEGRATOR_ID"));
});
