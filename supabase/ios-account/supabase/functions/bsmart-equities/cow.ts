import type { OrderQuoteRequest } from "npm:@cowprotocol/sdk-order-book@4.2.1";
import { readJSON } from "../bsmart-markets/providers.ts";
import { MarketError } from "../bsmart-markets/routing.ts";
import { NETWORKS } from "./assets.ts";
import type { QuoteRequest } from "./quote.ts";
import type { EVMInstrument } from "./routing.ts";

export function cowQuote(fetcher: typeof fetch = fetch) {
  return async (instrument: EVMInstrument, request: QuoteRequest): Promise<unknown> => {
    // SDK HTTP client cannot inject an AbortSignal. Keep the existing bounded transport;
    // official SDK types and fee/order math are used rather than recreating those rules.
    const body: OrderQuoteRequest = request;
    try {
      return await readJSON(`https://api.cow.fi/${NETWORKS[instrument.network].api}/api/v1/quote`, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
      }, fetcher);
    } catch { throw new MarketError("cow_quote_unavailable"); }
  };
}
