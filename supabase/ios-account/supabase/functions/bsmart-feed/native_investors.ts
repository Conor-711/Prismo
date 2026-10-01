import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import type { InfoReader } from "./verification.ts";
import { nativeFillHistory, openingSettlement } from "./opening_settlement.ts";

type Order = {
  id: string;
  source_kind: "opinion" | "direct";
  wallet: string;
  registered_at: string;
  intent: Record<string, unknown>;
  execution: Record<string, unknown>;
  opinion: Record<string, unknown> | null;
};

const amount = (value: unknown, signed = false): string | null =>
  typeof value === "string" && new RegExp(`^${signed ? "-?" : ""}\\d{1,20}(?:\\.\\d{1,18})?$`).test(value) &&
    Number.isFinite(Number(value)) ? value : null;
const walletPattern = /^0x[0-9a-f]{40}$/i;

function baseOpinion(order: Order) {
  if (order.source_kind === "direct") {
    const base = order.intent.baseActivity;
    return base && typeof base === "object" && ["subject", "native"].includes((base as any).kind)
      ? base : null;
  }
  if (order.source_kind !== "opinion" || !order.opinion) return null;
  const value = order.opinion;
  const name = typeof value.authorName === "string" ? value.authorName.slice(0, 80) : "";
  const body = typeof value.originalText === "string" && value.originalText.trim()
    ? value.originalText : typeof value.thesis === "string" ? value.thesis : "";
  if (!name.trim() || !body.trim()) return null;
  const avatarURL = typeof value.authorAvatarURL === "string" && value.authorAvatarURL.startsWith("https://")
    ? value.authorAvatarURL : null;
  const sourceURL = typeof value.sourceURL === "string" && value.sourceURL.startsWith("https://")
    ? value.sourceURL : null;
  return {
    kind: "opinion",
    opinionID: typeof value.id === "string" && /^[0-9a-f-]{36}$/i.test(value.id) ? value.id : null,
    authorID: typeof value.authorId === "string" ? value.authorId : null,
    ticker: typeof value.ticker === "string" ? value.ticker : null,
    companyName: typeof value.companyName === "string" ? value.companyName : null,
    platform: typeof value.platform === "string" ? value.platform : null,
    direction: typeof value.direction === "string" ? value.direction : null,
    publishedAt: typeof value.publishedAt === "string" ? value.publishedAt : null,
    sourceURL,
    thesis: typeof value.thesis === "string" ? value.thesis.slice(0, 8000) : null,
    authorName: name, avatarURL, body: body.slice(0, 8000),
  };
}

function positionFor(state: unknown, coin: string, side: string) {
  if (!state || typeof state !== "object" || !Array.isArray((state as any).assetPositions)) return null;
  const row = (state as any).assetPositions.find((item: any) => item?.type === "oneWay" && item?.position?.coin === coin);
  const p = row?.position;
  const size = Number(p?.szi), value = Number(p?.positionValue);
  if (!Number.isFinite(size) || size === 0 || !Number.isFinite(value) || value <= 0 ||
      (size > 0 ? "long" : "short") !== side) return null;
  const leverage = p.leverage?.value;
  const unrealizedPnlUSD = amount(p.unrealizedPnl, true);
  const currentPriceUSD = String(value / Math.abs(size));
  if (!Number.isInteger(leverage) || leverage <= 0 || leverage > 1000 ||
      !unrealizedPnlUSD || !Number.isFinite(Number(currentPriceUSD))) return null;
  return { leverage, unrealizedPnlUSD, currentPriceUSD };
}

function averageFillPrice(order: Order, fills: unknown): string | null {
  if (!Array.isArray(fills) || fills.length > 6000 || !Array.isArray(order.execution.fillIDs)) return null;
  const expected = new Set(order.execution.fillIDs.map(String));
  if (!expected.size || expected.size > 100) return null;
  const matched = fills.filter((fill: any) => expected.has(String(fill?.tid)) &&
    fill?.coin === order.execution.marketCoin && String(fill?.oid) === String(order.execution.orderID));
  if (matched.length !== expected.size || new Set(matched.map((fill: any) => String(fill.tid))).size !== expected.size) {
    return null;
  }
  let size = 0, value = 0;
  for (const fill of matched) {
    const quantity = Number(amount(fill.sz)), price = Number(amount(fill.px));
    if (!Number.isFinite(quantity) || !Number.isFinite(price) || quantity <= 0 || price <= 0) return null;
    size += quantity;
    value += quantity * price;
  }
  const average = value / size;
  return Number.isFinite(average) && average > 0 ? String(average) : null;
}

export async function enrichNativeInvestors(client: SupabaseClient, info: InfoReader, snapshot: any) {
  const observedAt = Date.now();
  if (!Array.isArray(snapshot?.profiles) || !Array.isArray(snapshot?.updates)) throw Error("invalid_snapshot");
  const updates = snapshot.updates.map((update: any) => ({ ...update, reducing: update.reducing === true }));
  const orders = new Map<string, Order>();
  for (let start = 0; start < updates.length; start += 100) {
    const ids = updates.slice(start, start + 100).map((update: any) => update.id);
    const result = await client.from("bsmart_feed_orders")
      .select("id,source_kind,wallet,registered_at,intent,execution,opinion").in("id", ids);
    if (result.error) throw Error("native_orders_unavailable");
    for (const order of result.data ?? []) if (order.execution) orders.set(order.id, order as Order);
  }

  const recent = updates.slice(0, 60).map((update: any) => orders.get(update.id)).filter(Boolean) as Order[];
  const currentOwner = new Map<string, string>();
  for (const update of updates) {
    const order = orders.get(update.id);
    if (!order || update.reducing) continue;
    const key = `${order.wallet}|${String(order.execution.marketCoin)}`;
    if (!currentOwner.has(key)) currentOwner.set(key, update.id);
  }
  const positions = new Map<string, unknown>();
  const fillsByWallet = new Map<string, unknown>();
  const positionKeys = new Set(recent.filter(order => order.intent.reduceOnly !== true)
    .map(order => `${order.wallet}|${String(order.execution.marketCoin).split(":").slice(0, -1).join(":")}`));
  await Promise.all([...positionKeys].slice(0, 20).map(async key => {
    const [wallet, dex] = key.split("|");
    if (!walletPattern.test(wallet)) return;
    try { positions.set(key, await info({ type: "clearinghouseState", user: wallet, dex })); }
    catch { /* Live position fields are omitted when the venue is unavailable. */ }
  }));
  const wallets = [...new Set(recent.map(order => order.wallet))].filter(wallet => walletPattern.test(wallet));
  await Promise.all(wallets.slice(0, 20).map(async wallet => {
    const own = recent.filter(order => order.wallet === wallet);
    const start = Math.min(...own.map(order => Date.parse(order.registered_at)));
    const end = observedAt;
    if (!Number.isFinite(start) || !Number.isFinite(end) || start > end) return;
    try {
      fillsByWallet.set(wallet, await nativeFillHistory(info, wallet, Math.floor(start), end));
    } catch { /* Verified notional and realized PnL remain usable without fill history. */ }
  }));

  return { ...snapshot, updates: updates.map((update: any) => {
    const order = orders.get(update.id);
    if (!order) return update;
    const reducing = update.reducing;
    const coin = String(order.execution.marketCoin ?? "");
    const dex = coin.includes(":") ? coin.split(":").slice(0, -1).join(":") : "";
    const key = `${order.wallet}|${dex}`;
    const live = !reducing && currentOwner.get(`${order.wallet}|${coin}`) === update.id && positions.has(key)
      ? positionFor(positions.get(key), coin, String(order.execution.side)) : null;
    const fillPrice = averageFillPrice(order, fillsByWallet.get(order.wallet));
    const settled = !reducing ? openingSettlement(order, fillsByWallet.get(order.wallet), observedAt) : null;
    const base = baseOpinion(order);
    const orderSide = String(order.execution.side);
    const positionSide = reducing
      ? orderSide === "long" ? "short" : orderSide === "short" ? "long" : null
      : orderSide;
    return { ...update, trade: {
      sourceKind: order.source_kind,
      eventKind: reducing ? "closing" : "opening",
      status: reducing || settled ? "closed" : live ? "open" : positions.has(key) ? "historical" : "unknown",
      marketCoin: coin,
      side: positionSide,
      notionalUSD: amount(order.execution.notionalUSD),
      leverage: settled ? null : live?.leverage ?? null,
      unrealizedPnlUSD: settled ? null : live?.unrealizedPnlUSD ?? null,
      realizedPnlUSD: reducing ? amount(order.execution.netRealizedPnlUSD, true) : settled?.realizedPnlUSD ?? null,
      entryPriceUSD: reducing ? null : fillPrice,
      currentPriceUSD: settled ? null : live?.currentPriceUSD ?? null,
      exitPriceUSD: reducing ? fillPrice : settled?.exitPriceUSD ?? null,
      base,
    } };
  }) };
}
