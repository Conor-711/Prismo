import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { MarketError } from "../bsmart-markets/routing.ts";
import { jsonBody } from "./http.ts";
import { createInput, expectedVersion, intentId, intentResponse, type Ledger, refreshable, requestHash, savedPreview } from "./intents.ts";
import { address } from "./quote.ts";
import { previewEquity, type PreviewPorts } from "./preview.ts";
import type { EVMCatalogs } from "./routing.ts";
import { fundingIntent, fundingPreview } from "./funding_preview.ts";
import type { FundingPorts } from "./funding_types.ts";
import { prepareIntent, type PreparationLedger } from "./preparations.ts";

export async function boundWallet(client: SupabaseClient, account: string) {
  const { data: wallet, error } = await client.from("bsmart_wallets").select("address").eq("account_id", account).maybeSingle();
  if (error || !wallet) throw new MarketError("wallet_unavailable");
  try { return address(wallet.address); } catch { throw new MarketError("wallet_unavailable"); }
}
export async function handleIntent(req: Request, account: string, client: SupabaseClient, options: {
  ledgerEnabled?: boolean; ledger?: Ledger; previewEnabled?: boolean; previewPorts?: PreviewPorts;
  fundingPreviewEnabled?: boolean; fundingPorts?: FundingPorts;
  preparationEnabled?: boolean; preparationLedger?: PreparationLedger;
  catalogs: EVMCatalogs; now?: () => number;
}): Promise<unknown | undefined> {
  const url = new URL(req.url), path = url.pathname;
  const match = path.match(/\/bsmart-equities\/intents(?:\/([^/]+)(?:\/(preview|cancel|funding-preview|prepare))?)?\/?$/);
  if (!match) return undefined;
  const [, id, action] = match;
  if ((!id && req.method !== "POST") || (id && !action && req.method !== "GET") || (action && req.method !== "POST")) return undefined;
  if (!options.ledgerEnabled || !options.ledger) throw new MarketError("ledger_disabled");
  if (url.search) throw new MarketError("invalid_intent", 422);
  const ledger = options.ledger;
  if (!id) {
    const input = createInput(await jsonBody(req)), owner = await boundWallet(client, account);
    const row = await ledger.create(account, owner, input.clientIntentId, input.input, await requestHash(account, owner, input.input));
    return intentResponse(row, await ledger.legs(account, row.id));
  }
  const uuid = intentId(id), row = await ledger.get(account, uuid);
  // Never rely solely on a service-role adapter's implicit filtering.
  if (row.account_id !== account || row.id !== uuid) throw new MarketError("intent_not_found", 404);
  if (!action) return intentResponse(row, await ledger.legs(account, uuid));
  const version = expectedVersion(await jsonBody(req));
  if (action === "cancel") return intentResponse(await ledger.change(account, uuid, row.wallet_address, version, "cancel"));
  if (action === "prepare") {
    if (!options.preparationEnabled || !options.preparationLedger || !options.previewEnabled || !options.previewPorts || !options.fundingPorts) {
      throw new MarketError("preparation_disabled");
    }
    return await prepareIntent(row, version, { ledger: options.preparationLedger, getIntent: ledger.get,
      boundOwner: () => boundWallet(client, account), assertIdle: options.fundingPorts.assertIdle,
      catalogs: options.catalogs, preview: options.previewPorts, now: options.now });
  }
  if (action === "funding-preview") {
    if (!options.fundingPreviewEnabled || !options.fundingPorts) throw new MarketError("funding_preview_disabled");
    const owner = await boundWallet(client, account);
    fundingIntent(row, owner, version, (options.now ?? Date.now)());
    const result = await fundingPreview(row, owner, options.catalogs, options.fundingPorts, options.now);
    const latest = await ledger.get(account, uuid);
    if (latest.account_id !== account || latest.id !== uuid) throw new MarketError("intent_not_found", 404);
    fundingIntent(latest, await boundWallet(client, account), version, (options.now ?? Date.now)());
    return result;
  }
  if (!options.previewEnabled || !options.previewPorts) throw new MarketError("preview_disabled");
  const owner = await boundWallet(client, account);
  refreshable(row, owner, version);
  const preview = await previewEquity(row.input, account, owner, options.catalogs, options.previewPorts, options.now);
  savedPreview(row, preview, (options.now ?? Date.now)());
  return intentResponse(await ledger.change(account, uuid, owner, version, "quote", preview));
}
