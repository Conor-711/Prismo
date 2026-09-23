import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { amountMicro, networks, RelayFunding, validAddress, type Network } from "./relay.ts";
import { stableAddress } from "./address_store.ts";

type Config = { enabled: boolean; relayKey: string };
const reply = (body: unknown, status = 200) => Response.json(body, {
  status, headers: { "Cache-Control": "no-store" },
});

export async function handle(req: Request, client: SupabaseClient, config: Config,
  provider = new RelayFunding(config.relayKey)): Promise<Response> {
  const path = new URL(req.url).pathname.replace(/\/$/, "").split("/bsmart-funding")[1];
  if (!((path === "" && req.method === "GET") || (["/quote", "/address"].includes(path) && req.method === "POST") ||
      (path === "/deposits" && req.method === "GET"))) return reply({ error: "not_found" }, 404);
  const bearer = req.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(bearer) || bearer.length > 16400) {
    return reply({ error: "unauthorized" }, 401);
  }
  try {
    const { data: { user }, error } = await client.auth.getUser(bearer.slice(7));
    if (error || !user || user.is_anonymous ||
        !user.identities?.some(i => ["apple", "google"].includes(i.provider))) return reply({ error: "unauthorized" }, 401);
    const { data: wallet, error: registryError } = await client.from("bsmart_wallets")
      .select("address").eq("account_id", user.id).maybeSingle();
    if (registryError) throw new Error("registry_unavailable");
    const owner = typeof wallet?.address === "string" ? wallet.address.toLowerCase() : "";
    const available = config.enabled && !!config.relayKey && validAddress(owner);
    if (path === "") return reply({ available });
    // History remains readable during an intake pause.
    if (path === "/deposits" && config.relayKey && validAddress(owner)) {
      return reply({ recipient: owner, deposits: await provider.deposits(owner) });
    }
    if (!available) return reply({ error: "funding_unavailable" }, 503);
    let input: { network: Network; amount?: string };
    try {
      if (!req.headers.get("content-type")?.startsWith("application/json")) throw new Error();
      const reader = req.body?.getReader();
      if (!reader) throw new Error();
      const bytes: number[] = [];
      try {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          if (bytes.length + value.length > 512) throw new Error();
          bytes.push(...value);
        }
      } finally { await reader.cancel(); }
      input = JSON.parse(new TextDecoder().decode(new Uint8Array(bytes)));
      const expected = path === "/address" ? "network" : "amount,network";
      if (!input || Object.keys(input).sort().join(",") !== expected ||
          !Object.hasOwn(networks, input.network)) throw new Error();
      if (path === "/quote") amountMicro(input.amount);
    } catch { return reply({ error: "invalid_input" }, 422); }
    return reply(path === "/address" ? await stableAddress(client, provider, user.id, owner, input.network)
      : await provider.quote(owner, input.network, input.amount!));
  } catch { return reply({ error: "funding_unavailable" }, 503); }
}
