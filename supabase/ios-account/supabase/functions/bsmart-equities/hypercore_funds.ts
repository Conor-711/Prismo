import { readJSON } from "../bsmart-markets/providers.ts";
import { parseUnits } from "npm:viem@2.56.3";
import { dexNames, MarketError, object } from "../bsmart-markets/routing.ts";
import { address } from "./quote.ts";
import type { HCFunds } from "./funding_types.ts";

const fail = () => new MarketError("hypercore_funds_unavailable");
function units(value: unknown) {
  if (typeof value !== "string" || !/^(0|[1-9][0-9]{0,11})(\.[0-9]{1,8})?$/.test(value)) throw fail();
  return parseUnits(value, 8);
}
export function spotFunds(value: unknown) {
  const rows = object(value).balances;
  if (!Array.isArray(rows) || rows.length > 2048) throw fail();
  const tokens = new Set<number>(); let available = 0n;
  for (const value of rows) {
    const r = object(value);
    if (!Number.isSafeInteger(r.token) || (r.token as number) < 0 || tokens.has(r.token as number) ||
      typeof r.coin !== "string" || !r.coin || (r.token === 0) !== (r.coin === "USDC")) throw fail();
    tokens.add(r.token as number);
    if (r.token === 0) {
      const total = units(r.total), hold = units(r.hold);
      if (hold > total) throw fail();
      available = total - hold;
      // In a unified account, free spot balance is not proof that margin is free.
      if (hold !== 0n) throw new MarketError("hypercore_margin_in_use", 409);
    }
  }
  return available.toString();
}
export function perpsFunds(value: unknown, now: number) {
  const r = object(value);
  if (!Number.isSafeInteger(r.time) || (r.time as number) > now + 5000 || now - (r.time as number) >= 30_000) throw fail();
  return units(r.withdrawable).toString();
}
export function hypercoreFunds(fetcher: typeof fetch = fetch, now: () => number = Date.now) {
  const info = (body: unknown) => readJSON("https://api.hyperliquid.xyz/info", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
  }, fetcher);
  return async (boundOwner: string): Promise<HCFunds> => {
    const owner = address(boundOwner), at = now();
    const time = () => { if (now() < at || now() - at >= 30_000) throw fail(); };
    try {
      const mode = await info({ type: "userAbstraction", user: owner }); time();
      if (!["default", "disabled", "dexAbstraction", "unifiedAccount", "portfolioMargin"].includes(mode as string)) throw fail();
      if (mode === "portfolioMargin") throw new MarketError("hypercore_portfolio_margin_unsupported", 409);
      let availableRaw: string;
      if (mode === "unifiedAccount") {
        const before = dexNames(await info({ type: "perpDexs" })); time();
        // Bounded batches cover every venue; an unread venue is never considered flat.
        for (let n = 0; n < before.length; n += 4) {
          await Promise.all(before.slice(n, n + 4).map(async dex => {
            const state = object(await info({ type: "clearinghouseState", user: owner, dex }));
            const orders = await info({ type: "openOrders", user: owner, dex });
            if (!Array.isArray(state.assetPositions) || !Array.isArray(orders)) throw fail();
            if (state.assetPositions.length || orders.length) throw new MarketError("hypercore_margin_in_use", 409);
          }));
          time();
        }
        if (JSON.stringify(before) !== JSON.stringify(dexNames(await info({ type: "perpDexs" })))) throw fail(); time();
        availableRaw = spotFunds(await info({ type: "spotClearinghouseState", user: owner }));
      } else {
        // accountValue includes locked margin and PnL; only withdrawable is spendable.
        availableRaw = perpsFunds(await info({ type: "clearinghouseState", user: owner }), now());
      }
      time();
      if (await info({ type: "userAbstraction", user: owner }) !== mode) throw new MarketError("hypercore_mode_changed", 409);
      time();
      return { owner, mode: mode as string, source: mode === "unifiedAccount" ? "HyperCoreSpot" : "HyperCorePerps",
        availableRaw, at, flatAccountChecked: mode === "unifiedAccount" };
    } catch (error) { throw error instanceof MarketError && error.code.startsWith("hypercore_") ? error : fail(); }
  };
}
