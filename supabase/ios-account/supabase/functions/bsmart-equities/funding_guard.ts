import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { MarketError } from "../bsmart-markets/routing.ts";
import { address } from "./quote.ts";
import { intentId } from "./intents.ts";

export function fundingGuard(client: SupabaseClient, includePreparations = false) {
  return async (account: string, boundOwner: string, currentIntent: string) => {
    const owner = address(boundOwner); intentId(account); intentId(currentIntent);
    const queries: PromiseLike<{ data: unknown; error: unknown }>[] = [
      client.from("bsmart_across_withdrawals").select("id").eq("wallet_address", owner)
        .in("state", ["quoted", "submitting", "submitted", "uncertain", "deposit_pending", "expired"]).limit(1),
      client.from("bsmart_withdrawals").select("id").eq("wallet_address", owner)
        .in("state", ["reserved", "submitting", "accepted", "uncertain", "core_debited"]).limit(1),
      client.from("bsmart_equity_intents").select("id").eq("wallet_address", owner).neq("id", currentIntent)
        .in("state", ["authorized", "funding_pending", "funded", "order_pending", "filled", "return_pending", "refund_pending", "needs_reconciliation"]).limit(1),
    ];
    if (includePreparations) queries.push(client.from("bsmart_equity_preparations").select("intent_id").eq("wallet_address", owner)
      .neq("intent_id", currentIntent).in("state", ["reserved", "signing", "authorized"]).limit(1));
    // Wallet-wide guard, including bindings in another account; no record details leave this layer.
    // This is not an atomic reservation and cannot see unrelated wallet activity.
    for (const query of queries) {
      const { data, error } = await query;
      if (error || !Array.isArray(data)) throw new MarketError("funding_state_unavailable");
      if (data.length) throw new MarketError("funding_activity_in_progress", 409);
    }
  };
}
