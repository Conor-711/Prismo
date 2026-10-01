import { strict as assert } from "node:assert";
import { nativeFillHistory, openingSettlement } from "../supabase/functions/bsmart-feed/opening_settlement.ts";
import { enrichNativeInvestors } from "../supabase/functions/bsmart-feed/native_investors.ts";

const start = Date.parse("2026-09-30T13:42:05.282Z"), end = Date.parse("2026-10-01T11:38:36.684Z");
function fixture(short = false) {
  const id = crypto.randomUUID(), coin = "xyz:AAPL";
  const order = { id, wallet: "0x" + "a".repeat(40), source_kind: "direct", opinion: null,
    registered_at: new Date(start - 1000).toISOString(), intent: { reduceOnly: false },
    execution: { marketCoin: coin, side: short ? "short" : "long", notionalUSD: "11.96928",
      orderID: "100", fillIDs: ["1"], lastFilledAt: new Date(start).toISOString() } };
  const common = { coin, hash: "0x" + "a".repeat(64), feeToken: "USDC" };
  const fills = [
    { ...common, tid: 1, oid: 100, time: start, startPosition: "0", sz: "0.036", px: "332.48",
      dir: short ? "Open Short" : "Open Long", side: short ? "A" : "B", closedPnl: "0", fee: "0.001077" },
    { ...common, tid: 2, oid: 101, time: end, startPosition: short ? "-0.036" : "0.036",
      sz: "0.036", px: "331.85", dir: short ? "Close Short" : "Close Long", side: short ? "B" : "A",
      closedPnl: short ? "0.02268" : "-0.02268", fee: "0.001075" },
  ];
  return { order, fills };
}

Deno.test("original AAPL opening settles with actual exit and both fees, never close notional", () => {
  const { order, fills } = fixture();
  assert.deepEqual(openingSettlement(order, fills, end), { exitPriceUSD: "331.85", realizedPnlUSD: "-0.024832" });
  assert.equal(order.execution.notionalUSD, "11.96928");
  const short = fixture(true);
  assert.equal(openingSettlement(short.order, short.fills, end)?.realizedPnlUSD, "0.020528");
});

Deno.test("partial closes aggregate weighted exit only once flat", () => {
  const { order, fills } = fixture();
  const half = { ...fills[1], sz: "0.018", px: "330", fee: "0.001", closedPnl: "-0.04464" };
  assert.equal(openingSettlement(order, [fills[0], half], end), null);
  const rest = { ...half, tid: 3, time: end + 1, startPosition: "0.018", px: "334", closedPnl: "0.02736" };
  assert.deepEqual(openingSettlement(order, [rest, fills[0], half], end + 1),
    { exitPriceUSD: "332", realizedPnlUSD: "-0.020357" });
});

Deno.test("partial opening fills reconcile before any reductions", () => {
  const { order, fills } = fixture();
  order.execution.fillIDs = ["1", "3"];
  order.execution.lastFilledAt = new Date(start + 1).toISOString();
  const first = { ...fills[0], sz: "0.018", fee: "0.0005" };
  const second = { ...first, tid: 3, time: start + 1, startPosition: "0.018" };
  assert.equal(openingSettlement(order, [first, second, fills[1]], end)?.realizedPnlUSD, "-0.024755");
});

Deno.test("reopenings and other assets do not change prior settlement", () => {
  const { order, fills } = fixture();
  const next = { ...fills[0], tid: 3, oid: 103, time: end + 1, px: "500" };
  assert.equal(openingSettlement(order, [...fills, next, { ...next, tid: 4, coin: "xyz:NVDA" }], end + 1)
    ?.exitPriceUSD, "331.85");
});

Deno.test("mixed positions, reversals, missing or inconsistent evidence fail closed", () => {
  for (const patch of [{ startPosition: "0.01" }, { sz: "0.04" }, { feeToken: "ETH" },
    { fee: undefined }, { closedPnl: "NaN" }, { time: end + 1 }, { hash: "0x" + "0".repeat(64) },
    { dir: "Long > Short" }]) {
    const { order, fills } = fixture();
    assert.equal(openingSettlement(order, [fills[0], { ...fills[1], ...patch }], end), null);
  }
  const { order, fills } = fixture();
  assert.equal(openingSettlement(order, [fills[1]], end), null);
  assert.equal(openingSettlement(order, [fills[0], fills[0], fills[1]], end), null);
  const added = { ...fills[0], tid: 3, oid: 105, time: start + 1, startPosition: "0.036" };
  assert.equal(openingSettlement(order, [fills[0], added, fills[1]], end), null);
  assert.equal(openingSettlement(order, [{ ...fills[0], startPosition: "1" }, fills[1]], end), null);
});

Deno.test("inclusive pagination deduplicates boundary fills and never accepts exhausted history", async () => {
  const batch = Array.from({ length: 2000 }, (_, tid) => ({ tid, time: start + tid }));
  let calls = 0;
  const result = await nativeFillHistory(async query => {
    calls++;
    if (calls === 1) return batch;
    assert.equal(query.startTime, batch[1999].time);
    return [batch[1999], { tid: 2000, time: start + 2000 }];
  }, "wallet", start, end);
  assert.equal(result?.length, 2001);
  assert.equal(calls, 2);
  calls = 0;
  assert.equal(await nativeFillHistory(async () => {
    const offset = calls++ * 2000;
    return batch.map(fill => ({ tid: fill.tid + offset, time: fill.time + offset }));
  }, "wallet", start, end), null);
  assert.equal(calls, 3);
  assert.equal(await nativeFillHistory(async () => batch.map(fill => ({ ...fill, time: start })),
    "wallet", start, end), null);
});

Deno.test("snapshot keeps original event fields and quote after verified round trip", async () => {
  const { order, fills } = fixture();
  order.intent = { reduceOnly: false, baseActivity: { kind: "subject", authorName: "Kevin Hern", body: "Sell AAPL" } } as any;
  const client: any = { from: () => ({ select: () => ({ in: async () => ({ data: [order], error: null }) }) }) };
  const result = await enrichNativeInvestors(client, async query =>
    query.type === "clearinghouseState" ? { assetPositions: [] } : fills,
    { profiles: [], updates: [{ id: order.id, reducing: false, body: "My thesis" }] });
  const update = result.updates[0];
  assert.equal(update.body, "My thesis");
  assert.equal(update.trade.eventKind, "opening");
  assert.equal(update.trade.status, "closed");
  assert.equal(update.trade.notionalUSD, "11.96928");
  assert.equal(update.trade.entryPriceUSD, "332.48");
  assert.equal(update.trade.exitPriceUSD, "331.85");
  assert.equal(update.trade.realizedPnlUSD, "-0.024832");
  assert.equal(update.trade.base.authorName, "Kevin Hern");
});
