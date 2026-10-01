import { strict as assert } from "node:assert";
import { rankCandidates } from "../scripts/select_xstocks_candidates.ts";
const usdc = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
function asset(ticker: string, id: string) {
  return { id, symbol: ticker + "x", name: ticker + " xStock", isTradingHalted: false,
    underlying: { symbol: ticker, currency: "USD" }, deployments: [{ network: "Ethereum",
      address: "0x1111111111111111111111111111111111111111",
      stablecoins: [{ network: "Ethereum", symbol: "USDC", address: usdc, decimals: 6 }] }] };
}
const one = asset("SPY", "84f38991-b86c-470e-9d19-540197c19fd1");
const two = asset("ASTS", "84f38991-b86c-470e-9d19-540197c19fd2");
function registry(nodes: unknown[]) { return { completeRegistry: true, executionEnabled: false, nodes }; }
function popularity(nodes: unknown[]) { return { source: "bsmart_x_opinion_committed_snapshot", metric: "distinct_ticker_tweet_count", nodes }; }
Deno.test("selection uses observed popularity and excludes all active HL collateral types", () => {
  const p = popularity([{ ticker: "SPY", mentions: 100, authors: 10 }, { ticker: "ASTS", mentions: 50, authors: 5 }]);
  const r = rankCandidates(registry([two, one]), p, [], 1);
  assert.deepEqual(r.candidates.map(c => c.ticker), ["SPY"]);
  assert.equal(r.eligibleCount, 2);
  const hl = [{ coin: "xyz:SPY", dex: "xyz", collateralToken: 7, maxLeverage: 10, delisted: false }];
  assert.deepEqual(rankCandidates(registry([one, two]), p, hl, 50).candidates.map(c => c.ticker), ["ASTS"]);
});
Deno.test("partial or ambiguous registry cannot create a shortlist", () => {
  const p = popularity([{ ticker: "SPY", mentions: 100, authors: 10 }]);
  assert.throws(() => rankCandidates({ ...registry([one]), completeRegistry: false }, p, [], 50));
  assert.throws(() => rankCandidates(registry([one, one]), p, [], 50));
  assert.throws(() => rankCandidates(registry([one, { ...one, id: two.id }]), p, [], 50));
});
Deno.test("invalid and duplicate popularity counts fail closed", () => {
  for (const counts of [{ mentions: -1, authors: 1 }, { mentions: 1.5, authors: 1 }, { mentions: 1, authors: 2 }]) {
    assert.throws(() => rankCandidates(registry([one]), popularity([{ ticker: "SPY", ...counts }]), [], 50));
  }
  const m = { ticker: "SPY", mentions: 100, authors: 1 };
  assert.throws(() => rankCandidates(registry([one]), popularity([m, m]), [], 50));
});
Deno.test("halting, wrong USDC and daily-reset leverage do not pad the target count", () => {
  const leveraged = asset("TQQQ", "84f38991-b86c-470e-9d19-540197c19fd3");
  const halted = { ...two, isTradingHalted: true };
  const invalid = asset("OUST", "84f38991-b86c-470e-9d19-540197c19fd4");
  invalid.deployments[0].stablecoins[0].address = invalid.deployments[0].address;
  const metrics = [one, leveraged, halted, invalid].map((a, i) => ({ ticker: a.underlying.symbol, mentions: 100 - i, authors: 1 }));
  const r = rankCandidates(registry([one, leveraged, halted, invalid]), popularity(metrics), [], 50);
  assert.deepEqual(r.candidates.map(c => c.ticker), ["SPY"]);
  assert.equal(r.eligibleCount, 1);
});
