import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";
import { handleNotifications } from "./handler.ts";

const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});
Deno.serve(request => handleNotifications(request, {
  async getUser(token) {
    const { data, error } = await client.auth.getUser(token);
    return { user: data.user, unavailable: !!error && (!error.status || error.status >= 500 || error.status === 429) };
  },
  async rpc(name, parameters) {
    const { data, error } = await client.rpc(name, parameters);
    return !error && data !== false;
  },
}));
