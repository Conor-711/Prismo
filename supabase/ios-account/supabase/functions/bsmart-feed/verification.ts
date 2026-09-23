// Read-only mainnet verification. No client-provided fill is accepted.
export type Intent = {
  opinionId: string; authorId: string; ticker: string; cloid: string; coin: string;
  side: "buy" | "sell"; size: string; limitPrice: string; nonce: number; expiresAfter: number;
};
export type RegisteredOrder = {
  id: string; wallet: string; intent: Intent; registered_at: string;
};
export type InfoReader = (body: Record<string, unknown>) => Promise<any>;
export const uuid = (s: unknown): s is string => typeof s === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);

// Fixed 18 decimal places cover the venue's wire values without binary float loss.
export function decimal(value: unknown): bigint {
  if (typeof value !== "string" || value.length > 48 || !/^\d{1,20}(\.\d{1,18})?$/.test(value)) {
    throw new Error("invalid_decimal");
  }
  const [whole, fraction = ""] = value.split(".");
  return BigInt(whole) * 10n ** 18n + BigInt(fraction.padEnd(18, "0"));
}
function wire(value: bigint, scale: number): string {
  const digits = value.toString().padStart(scale + 1, "0");
  return (digits.slice(0, -scale) + "." + digits.slice(-scale)).replace(/\.?0+$/, "");
}

export function validateIntent(input: any, now = Date.now()): Intent {
  const keys = ["opinionId", "authorId", "ticker", "cloid", "coin", "side", "size", "limitPrice", "nonce", "expiresAfter"];
  if (!input || typeof input !== "object" || Object.keys(input).length !== keys.length ||
      !keys.every(k => k in input) || !uuid(input.opinionId) ||
      typeof input.authorId !== "string" || !input.authorId.length || input.authorId.length > 256 ||
      typeof input.ticker !== "string" || !/^[a-zA-Z0-9_-]{1,64}$/.test(input.ticker) ||
      typeof input.coin !== "string" || !/^[a-zA-Z0-9_-]{1,64}:[a-zA-Z0-9_-]{1,64}$/.test(input.coin) ||
      !/^0x[0-9a-f]{32}$/.test(input.cloid) || /^0x0+$/.test(input.cloid) ||
      !["buy", "sell"].includes(input.side) || decimal(input.size) <= 0n || decimal(input.limitPrice) <= 0n ||
      !Number.isSafeInteger(input.nonce) || !Number.isSafeInteger(input.expiresAfter) ||
      now - input.nonce > 60000 || input.nonce > now + 5000 || input.expiresAfter <= now ||
      input.expiresAfter <= input.nonce || input.expiresAfter - input.nonce > 60000) {
    throw new Error("invalid_intent");
  }
  return { ...input, opinionId: input.opinionId.toLowerCase() };
}

export async function verifyHip3Market(intent: Intent, info: InfoReader): Promise<void> {
  const [dex, symbol] = intent.coin.split(":");
  if (symbol !== intent.ticker) throw new Error("market_unavailable");
  const dexs = await info({ type: "perpDexs" });
  if (!Array.isArray(dexs) || dexs[0] !== null) throw new Error("upstream_unavailable");
  if (!dexs.slice(1).some((entry: any) => entry?.name === dex)) throw new Error("market_unavailable");

  const meta = await info({ type: "meta", dex });
  if (!meta || !Array.isArray(meta.universe) || !Number.isInteger(meta.collateralToken)) {
    throw new Error("upstream_unavailable");
  }
  const market = meta.universe.find((entry: any) => entry?.name === intent.coin);
  if (!market || market.isDelisted === true || meta.collateralToken !== 0 ||
      !Number.isInteger(market.maxLeverage) || market.maxLeverage <= 0 ||
      !Number.isInteger(market.szDecimals) || market.szDecimals < 0 || market.szDecimals > 6) {
    throw new Error("market_unavailable");
  }
}

export async function verifyExecution(record: RegisteredOrder, info: InfoReader, now = Date.now()) {
  const i = record.intent, registered = Date.parse(record.registered_at);
  if (!Number.isFinite(registered)) throw new Error("invalid_registration");
  const result = await info({ type: "orderStatus", user: record.wallet, oid: i.cloid });
  if (result?.status === "unknownOid") return null;
  const status = result?.order?.status, order = result?.order?.order;
  if (result?.status !== "order" || !order || order.cloid !== i.cloid || order.coin !== i.coin ||
      order.side !== (i.side === "buy" ? "B" : "A") || order.reduceOnly !== false ||
      order.isTrigger !== false || !["Ioc", "FrontendMarket"].includes(order.tif) ||
      decimal(order.origSz) !== decimal(i.size) || decimal(order.limitPx) !== decimal(i.limitPrice) ||
      !Number.isSafeInteger(order.oid) || order.oid <= 0 || !Number.isSafeInteger(order.timestamp) ||
      order.timestamp < registered || order.timestamp > i.expiresAfter || order.timestamp > now) {
    throw new Error("order_mismatch");
  }
  if (!["filled", "canceled", "iocCancelRejected"].includes(status)) return null;
  const closedAt = result.order.statusTimestamp;
  if (!Number.isSafeInteger(closedAt) || closedAt < order.timestamp || closedAt > now) throw new Error("invalid_terminal_time");
  const rows = await info({ type: "userFillsByTime", user: record.wallet,
    startTime: Math.floor(registered), endTime: i.expiresAfter + 2000, aggregateByTime: false });
  if (!Array.isArray(rows) || rows.length >= 2000) throw new Error("incomplete_fills");
  let total = 0n, notional = 0n, first = Infinity, last = 0;
  const ids = new Set<number>();
  for (const f of rows.filter(f => f.oid === order.oid)) {
    if (f.coin !== i.coin || f.side !== order.side || !Number.isSafeInteger(f.tid) || f.tid < 0 || ids.has(f.tid) ||
        !Number.isSafeInteger(f.time) || f.time < registered || f.time < order.timestamp || f.time > now ||
        f.time > i.expiresAfter + 2000 || f.time > closedAt || !/^0x[0-9a-fA-F]{64}$/.test(f.hash) || /^0x0+$/.test(f.hash)) {
      throw new Error("fill_mismatch");
    }
    const size = decimal(f.sz), price = decimal(f.px), limit = decimal(i.limitPrice);
    if (size <= 0n || price <= 0n || (i.side === "buy" ? price > limit : price < limit)) {
      throw new Error("invalid_fill");
    }
    ids.add(f.tid); total += size; notional += size * price;
    first = Math.min(first, f.time); last = Math.max(last, f.time);
  }
  if (total > decimal(i.size) || (status === "filled" && total !== decimal(i.size))) throw new Error("incomplete_fills");
  if (total === 0n) return null;
  return { side: i.side === "buy" ? "long" : "short", notionalUSD: wire(notional, 36),
    marketCoin: i.coin, executedAt: new Date(first).toISOString(), lastFilledAt: new Date(last).toISOString(),
    orderID: String(order.oid), fillIDs: [...ids].map(String) };
}

export async function boundedJSON(url: string, init: RequestInit = {}, limit = 1048576): Promise<any> {
  const response = await fetch(url, { ...init, redirect: "error", signal: AbortSignal.timeout(10000) });
  if (!response.ok || !response.headers.get("content-type")?.includes("application/json")) throw new Error("upstream_unavailable");
  const reader = response.body!.getReader(), chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.length; if (size > limit) throw new Error("response_too_large");
      chunks.push(value);
    }
  } finally { await reader.cancel(); }
  const data = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(data));
}
