import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { MarketError } from "../bsmart-markets/routing.ts";
import { assertStoredPreparation, type PreparationLedger, type PreparationRow } from "./preparations.ts";

const conflicts = new Set(["preparation_conflict", "intent_version_conflict", "intent_state_conflict", "wallet_changed",
  "wallet_activity_in_progress", "quote_expired", "return_authorization_unavailable"]);
function failed(error: { message?: string; code?: string } | null): never {
  const message = error?.message ?? "";
  if (conflicts.has(message)) throw new MarketError(message, 409);
  if (message === "intent_not_found") throw new MarketError(message, 404);
  if (error?.code === "23505") throw new MarketError("preparation_conflict", 409);
  throw new MarketError("preparation_ledger_unavailable");
}
export function preparationLedger(client: SupabaseClient): PreparationLedger {
  async function verified(data: unknown, account: string, id: string) {
    const row = data as PreparationRow;
    await assertStoredPreparation(row, account, id);
    return row;
  }
  return {
    get: async (account, id) => {
      const { data, error } = await client.from("bsmart_equity_preparations").select("*")
        .eq("account_id", account).eq("intent_id", id).maybeSingle();
      if (error) failed(error);
      return data ? await verified(data, account, id) : null;
    },
    reserve: async (row, owner, version, preview, material, prepared, hash) => {
      const { data, error } = await client.rpc("bsmart_equity_prepare", { p_account: row.account_id, p_id: row.id,
        p_owner: owner, p_version: version, p_preview: preview, p_material: material, p_prepared: prepared, p_hash: hash });
      if (error || !data) failed(error);
      return await verified(data, row.account_id, row.id);
    },
    authorize: async (row, signature, hash) => {
      const { data, error } = await client.rpc("bsmart_equity_authorize_prepared", { p_account: row.account_id, p_id: row.intent_id,
        p_owner: row.wallet_address, p_version: row.intent_version, p_hash: row.preparation_hash,
        p_signature: signature, p_authorization_hash: hash });
      if (error || !data) failed(error);
      return await verified(data, row.account_id, row.intent_id);
    },
    startSigning: async row => {
      const { data, error } = await client.rpc("bsmart_equity_signing_start", { p_account: row.account_id, p_id: row.intent_id,
        p_owner: row.wallet_address, p_version: row.intent_version, p_hash: row.preparation_hash });
      if (error || !data) failed(error);
      return await verified(data, row.account_id, row.intent_id);
    },
  };
}
