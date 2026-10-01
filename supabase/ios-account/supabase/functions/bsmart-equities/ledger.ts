import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { MarketError } from "../bsmart-markets/routing.ts";
import { type IntentRow, type Ledger, savedPreview } from "./intents.ts";

const conflicts = new Set(["intent_idempotency_conflict", "intent_version_conflict", "intent_state_conflict", "wallet_changed", "intent_limit", "preparation_conflict"]);
function databaseError(error: { message?: string } | null): never {
  const code = error?.message ?? "";
  if (conflicts.has(code)) throw new MarketError(code, 409);
  if (code === "intent_not_found") throw new MarketError(code, 404);
  throw new MarketError("ledger_unavailable");
}
export function equityLedger(client: SupabaseClient, now: () => number = Date.now): Ledger {
  async function get(account: string, id: string): Promise<IntentRow> {
    const { data, error } = await client.from("bsmart_equity_intents").select("*")
      .eq("account_id", account).eq("id", id).maybeSingle();
    if (error) databaseError(error);
    if (!data) throw new MarketError("intent_not_found", 404);
    return data as IntentRow;
  }
  return {
    get,
    create: async (account, owner, clientId, input, hash) => {
      const { data, error } = await client.rpc("bsmart_equity_intent_create", {
        p_account: account, p_owner: owner, p_client_id: clientId, p_input: input, p_hash: hash,
      });
      if (error || !data) databaseError(error);
      return data as IntentRow;
    },
    legs: async (account, id) => {
      const { data, error } = await client.from("bsmart_equity_legs")
        .select("id,kind,leg_index,source_network,destination_network,state,provider,provider_id,attempts,checked_at")
        .eq("account_id", account).eq("intent_id", id).order("created_at", { ascending: true });
      if (error || !data) databaseError(error);
      return data;
    },
    change: async (account, id, owner, version, action, preview) => {
      if (action === "quote") {
        const row = await get(account, id);
        if (!preview) throw new MarketError("invalid_saved_preview");
        savedPreview(row, preview, now());
      }
      const { data, error } = await client.rpc("bsmart_equity_intent_change", {
        p_account: account, p_id: id, p_owner: owner, p_version: version, p_action: action, p_preview: preview ?? null,
      });
      if (error || !data) databaseError(error);
      return data as IntentRow;
    },
  };
}
