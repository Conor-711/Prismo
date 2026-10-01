import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { handleEquities } from "./handler.ts";
import { equityProviders } from "./providers.ts";
import { chainReader } from "./chain.ts";
import { cowQuote } from "./cow.ts";
import { equityLedger } from "./ledger.ts";
import { snapshotRegistry, storageSnapshot } from "./catalog_snapshot.ts";
import { hypercoreFunds } from "./hypercore_funds.ts";
import { relayFundingQuote } from "./relay_funding.ts";
import { fundingGuard } from "./funding_guard.ts";
import { preparationLedger } from "./preparation_ledger.ts";

const url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !key) throw new Error("Supabase runtime configuration missing");
const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
const catalogs = equityProviders(fetch, Date.now, Deno.env.get("BSMART_EQUITIES_CATALOG_SNAPSHOT_ENABLED") === "true"
  ? snapshotRegistry(storageSnapshot(client)) : undefined);
const previewPorts = { quote: cowQuote(), state: chainReader({
  Ethereum: Deno.env.get("BSMART_EQUITIES_ETHEREUM_RPC_URL"), Ink: Deno.env.get("BSMART_EQUITIES_INK_RPC_URL"),
}) };
const preparationEnabled = Deno.env.get("BSMART_EQUITIES_PREPARATION_ENABLED") === "true";
Deno.serve(req => handleEquities(req, client, {
  catalogs, discoveryEnabled: Deno.env.get("BSMART_EQUITIES_DISCOVERY_ENABLED") === "true",
  previewEnabled: Deno.env.get("BSMART_EQUITIES_PREVIEW_ENABLED") === "true", previewPorts,
  ledgerEnabled: Deno.env.get("BSMART_EQUITIES_LEDGER_ENABLED") === "true", ledger: equityLedger(client),
  fundingPreviewEnabled: Deno.env.get("BSMART_EQUITIES_FUNDING_PREVIEW_ENABLED") === "true",
  preparationEnabled, preparationLedger: preparationLedger(client),
  fundingPorts: { state: previewPorts.state, hypercore: hypercoreFunds(),
    bridge: relayFundingQuote(Deno.env.get("BSMART_RELAY_API_KEY")), assertIdle: fundingGuard(client, preparationEnabled) },
}));
