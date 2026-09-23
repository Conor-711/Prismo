import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { handleProfile } from "./handler.ts";

const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
Deno.serve(req => handleProfile(req, client));
