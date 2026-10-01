import { decimal, type InfoReader } from "./verification.ts";

type OpeningOrder = {
  registered_at: string;
  intent: Record<string, unknown>;
  execution: Record<string, unknown>;
};

function signed(value: unknown): bigint {
  if (typeof value !== "string") throw Error("invalid_decimal");
  return value.startsWith("-") ? -decimal(value.slice(1)) : decimal(value);
}

function wire(value: bigint): string {
  const negative = value < 0n, digits = (negative ? -value : value).toString().padStart(19, "0");
  return (negative ? "-" : "") + (digits.slice(0, -18) + "." + digits.slice(-18)).replace(/\.?0+$/, "");
}

export async function nativeFillHistory(info: InfoReader, wallet: string, start: number, end: number) {
  const rows = new Map<number, any>();
  let cursor = start;
  for (let page = 0; page < 3; page++) {
    const batch = await info({ type: "userFillsByTime", user: wallet,
      startTime: cursor, endTime: end, aggregateByTime: false });
    if (!Array.isArray(batch) || batch.length > 2000) return null;
    for (const fill of batch) {
      if (!Number.isSafeInteger(fill?.tid) || fill.tid < 0 || !Number.isSafeInteger(fill.time) ||
          fill.time < cursor || fill.time > end) return null;
      const previous = rows.get(fill.tid);
      if (previous && JSON.stringify(previous) !== JSON.stringify(fill)) return null;
      rows.set(fill.tid, fill);
    }
    if (batch.length < 2000) return [...rows.values()];
    const next = Math.max(...batch.map(fill => fill.time));
    // Inclusive boundary retains fills sharing a millisecond; no progress is unknown.
    if (next <= cursor) return null;
    cursor = next;
  }
  return null;
}

export function openingSettlement(order: OpeningOrder, fills: unknown, now: number) {
  try {
    if (order.intent.reduceOnly === true || !Array.isArray(fills) || fills.length > 6000 ||
        !Array.isArray(order.execution.fillIDs) || !order.execution.fillIDs.length) return null;
    const expected = new Set(order.execution.fillIDs.map(String));
    if (expected.size !== order.execution.fillIDs.length) return null;
    const coin = order.execution.marketCoin, side = order.execution.side;
    if (typeof coin !== "string" || !["long", "short"].includes(String(side))) return null;
    const openingSide = side === "long" ? "B" : "A", sign = side === "long" ? 1n : -1n;
    const registered = Date.parse(order.registered_at);
    const lastOpening = Date.parse(String(order.execution.lastFilledAt));
    if (!Number.isFinite(registered) || !Number.isFinite(lastOpening) || lastOpening > now) return null;
    const matched = fills.filter(fill => expected.has(String(fill?.tid)) && fill.coin === coin &&
      String(fill.oid) === String(order.execution.orderID));
    if (matched.length !== expected.size) return null;
    const start = Math.min(...matched.map(fill => fill.time));
    if (!Number.isSafeInteger(start) || start < registered) return null;
    const rows = fills.filter(fill => fill?.coin === coin && fill.time >= start)
      .sort((a, b) => a.time - b.time || a.tid - b.tid);
    const seen = new Set<number>(), opened = new Set<string>();
    let position = 0n, openSize = 0n, openValue = 0n, closeSize = 0n, closeValue = 0n;
    let pnl = 0n, fees = 0n;
    for (const fill of rows) {
      if (!Number.isSafeInteger(fill.tid) || fill.tid < 0 || seen.has(fill.tid) ||
          !Number.isSafeInteger(fill.oid) || fill.oid <= 0 || !Number.isSafeInteger(fill.time) ||
          fill.time > now || typeof fill.hash !== "string" || !/^0x[0-9a-f]{64}$/i.test(fill.hash) ||
          /^0x0+$/i.test(fill.hash) || fill.feeToken?.trim() !== "USDC") return null;
      seen.add(fill.tid);
      const size = decimal(fill.sz), price = decimal(fill.px);
      if (size <= 0n || price <= 0n || signed(fill.startPosition) !== position * sign) return null;
      const fee = signed(fill.fee), closedPnl = signed(fill.closedPnl);
      if (expected.has(String(fill.tid))) {
        if (closeSize > 0n || String(fill.oid) !== String(order.execution.orderID) ||
            fill.side !== openingSide || fill.time > lastOpening || closedPnl !== 0n ||
            fill.dir !== (side === "long" ? "Open Long" : "Open Short")) return null;
        opened.add(String(fill.tid));
        position += size; openSize += size; openValue += size * price;
      } else {
        // No attribution guess when another opening order is mixed into this position.
        if (opened.size !== expected.size || fill.side === openingSide ||
            fill.side !== (openingSide === "B" ? "A" : "B") || size > position ||
            fill.dir !== (side === "long" ? "Close Long" : "Close Short")) return null;
        position -= size; closeSize += size; closeValue += size * price;
        pnl += closedPnl;
      }
      fees += fee;
      if (position === 0n && closeSize > 0n) {
        if (openSize !== closeSize || openValue !== decimal(order.execution.notionalUSD) * 10n ** 18n) return null;
        return { exitPriceUSD: wire(closeValue / closeSize), realizedPnlUSD: wire(pnl - fees) };
      }
    }
  } catch { /* Invalid or incomplete evidence never becomes a fabricated settlement. */ }
  return null;
}
