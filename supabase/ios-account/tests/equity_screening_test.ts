import { strict as assert } from "node:assert";
import { hlMatches, parseAsset, parseQuote, roundTripDifference } from "../scripts/screen_xstocks.ts";

const usdc = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", token = "0x1111111111111111111111111111111111111111";
const assertEquals: typeof assert.deepEqual = assert.deepEqual;
const assertThrows: typeof assert.throws = assert.throws;
function asset() {
  return { id: "84f38991-b86c-470e-9d19-540197c19fd1", symbol: "OUSTx", name: "Ouster xStock", isTradingHalted: false,
    underlying: { symbol: "OUST", currency: "USD" }, trading: { isTradingHalted: false, tradingHoursMode: "TwentyFourFive" },
    deployments: [{ network: "Ethereum", address: token, stablecoins: [{ network: "Ethereum", symbol: "USDC", address: usdc, decimals: 6 }] }] };
}
Deno.test("screening excludes active HL markets even with unsupported collateral", () => {
  assertEquals(hlMatches("OUST", [{ coin: "xyz:OUST", dex: "xyz", collateralToken: 7, maxLeverage: 10, delisted: false }]), ["xyz:OUST"]);
  assertEquals(hlMatches("OUST", [{ coin: "xyz:OUST", dex: "xyz", collateralToken: 0, maxLeverage: 10, delisted: true }]), []);
});
Deno.test("issuer 24/5 primary hours do not imply a secondary-market halt", () => {
  assertEquals(parseAsset(asset(), "OUST").halted, false);
  const halted = asset(); halted.trading.isTradingHalted = true;
  assertEquals(parseAsset(halted, "OUST").halted, true);
});
Deno.test("issuer identity, USDC and network ambiguity fail closed", () => {
  assertThrows(() => parseAsset(asset(), "ALAB"));
  const wrong = asset(); wrong.deployments[0].stablecoins[0].address = token;
  assertThrows(() => parseAsset(wrong, "OUST"));
  const duplicate = asset(); duplicate.deployments.push(duplicate.deployments[0]);
  assertThrows(() => parseAsset(duplicate, "OUST"));
});
Deno.test("quote preserves fee-inclusive budget without upgrading unverified quotes", () => {
  const q = { from: "0x0000000000000000000000000000000000000001", verified: false,
    quote: { sellToken: usdc, buyToken: token, kind: "sell", sellAmount: "99000000", feeAmount: "1000000", buyAmount: "123456789000000000" } };
  assertEquals(parseQuote(q, usdc, token, "100000000").verified, false);
  assertThrows(() => parseQuote(q, usdc, token, "99000000"));
  assertThrows(() => parseQuote({ ...q, verified: undefined }, usdc, token, "100000000"));
  assertThrows(() => parseQuote(q, token, usdc, "100000000"));
});
Deno.test("screening accepts only distinct current wrapper addresses", () => {
  const a = asset(), wrapper = "0x2222222222222222222222222222222222222222";
  const withWrapper = (address: string) => ({ ...a, deployments: [{ ...a.deployments[0], wrapperAddressV2: address }] });
  assertEquals(parseAsset(withWrapper(wrapper), "OUST").deployments[0].wrapperV2, wrapper);
  assertEquals(parseAsset(a, "OUST").deployments[0].wrapperV2, null);
  for (const address of [token, usdc, "0x" + "0".repeat(40), "not-an-address"]) {
    assertThrows(() => parseAsset(withWrapper(address), "OUST"));
  }
});
Deno.test("malformed and zero quote amounts cannot pass screening", () => {
  const q = { from: "0x0000000000000000000000000000000000000001", verified: false,
    quote: { sellToken: usdc, buyToken: token, kind: "sell", sellAmount: "99000000", feeAmount: "1000000", buyAmount: "1" } };
  for (const buyAmount of ["0", "-1", "1.5", "01", (2n ** 256n).toString()]) {
    assertThrows(() => parseQuote({ ...q, quote: { ...q.quote, buyAmount } }, usdc, token, "100000000"));
  }
  assertThrows(() => parseQuote({ ...q, from: token }, usdc, token, "100000000"));
  assertThrows(() => parseQuote({ ...q, quote: { ...q.quote, kind: "buy" } }, usdc, token, "100000000"));
});
Deno.test("roundtrip computes quote difference, retaining favorable price changes", () => {
  assertEquals(roundTripDifference("1000000000", "982563019"), 1.743698);
  assertEquals(roundTripDifference("1000000000", "1010000000"), -1);
  assertThrows(() => roundTripDifference("0", "1"));
});
