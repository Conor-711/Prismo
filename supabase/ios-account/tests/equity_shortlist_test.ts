import { strict as assert } from "node:assert";
import { finalizeShortlist } from "../scripts/finalize_xstocks_shortlist.ts";
const c = { ticker: "ASTS", symbol: "ASTSx", assetId: "one", mentions: 100 };
const selection = { executionEnabled: false, candidates: [c] };
function report(difference = 1, amount = 1000) {
  return { executionEnabled: false, syntheticQuoteAccount: true, results: [{ ticker: "ASTS", disposition: "two_way_indicative",
    asset: { id: "one", symbol: "ASTSx", ticker: "ASTS", halted: false, deployments: [{ network: "Ink", token: "token" }] },
    probes: [{ executable: false, variant: "raw", network: "Ink", token: "token", amountUSDC: amount,
      roundTripDifferencePct: difference, buy: { verified: false, observedAt: "2026-10-01T08:00:00Z" },
      sell: { verified: false, observedAt: "2026-10-01T08:00:01Z" } }] }] };
}
Deno.test("expanded shortlist remains research-only and preserves HL-first", () => {
  const r = finalizeShortlist(selection, [report()], []);
  assert.equal(r.candidates.length, 1);
  assert.equal(r.executionEnabled, false);
  assert.equal(r.returnTransferImplemented, false);
  const hl = [{ coin: "xyz:ASTS", dex: "xyz", collateralToken: 0, maxLeverage: 5, delisted: false }];
  assert.equal(finalizeShortlist(selection, [report()], hl).candidates.length, 0);
});
Deno.test("small-only and expensive quotes remain transparent reserves", () => {
  assert.equal(finalizeShortlist(selection, [report(1, 100)], []).reserves[0].reason, "no_1000_two_way_observation");
  assert.equal(finalizeShortlist(selection, [report(8)], []).reserves[0].reason, "high_reference_difference");
});
Deno.test("failed amount tiers do not discard successful pairs", () => {
  const r = report();
  const mixed = { ...r, results: [{ ...r.results[0], probes: [{ error: "cow_404_NoLiquidity" }, ...r.results[0].probes] }] };
  assert.equal(finalizeShortlist(selection, [mixed], []).candidates.length, 1);
});
Deno.test("report and token identities cannot silently change", () => {
  const r = report();
  r.results[0].asset.id = "another";
  assert.throws(() => finalizeShortlist(selection, [r], []));
  const p = report();
  p.results[0].probes[0].token = "another";
  assert.throws(() => finalizeShortlist(selection, [p], []));
  assert.throws(() => finalizeShortlist({ ...selection, candidates: [c, c] }, [report()], []));
});
