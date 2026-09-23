import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import type { InfoReader } from "./verification.ts";

const addressPattern = /^0x[0-9a-f]{40}$/;
const coinPattern = /^[a-zA-Z0-9_-]+(?::[a-zA-Z0-9_-]+)?$/;
const amountPattern = /^-?\d{1,20}(?:\.\d{1,18})?$/;

function amount(value: unknown): string {
  if (typeof value !== "string" || !amountPattern.test(value) || !Number.isFinite(Number(value))) {
    throw new Error("invalid_portfolio");
  }
  return value;
}

function history(value: unknown): { at: number; valueUSD: string }[] {
  if (!Array.isArray(value) || value.length > 10000) throw new Error("invalid_portfolio");
  const points = value.map((row: unknown) => {
    if (!Array.isArray(row) || row.length !== 2 || !Number.isSafeInteger(row[0]) || row[0] < 0) {
      throw new Error("invalid_portfolio");
    }
    return { at: row[0] as number, valueUSD: amount(row[1]) };
  });
  if (points.some((point, index) => index > 0 && point.at <= points[index - 1].at)) {
    throw new Error("invalid_portfolio");
  }
  // The chart needs shape, not thousands of points on a phone.
  const stride = Math.max(1, Math.ceil(points.length / 120));
  return points.filter((_, index) => index % stride === 0 || index === points.length - 1);
}

export function parsePublicPortfolio(dexs: unknown, states: unknown[], spot: unknown, portfolio: unknown) {
  if (!Array.isArray(dexs) || dexs.length < 1 || dexs.length > 100 || dexs[0] !== null ||
      dexs.some((row, index) => index > 0 && (typeof row?.name !== "string" || !/^[a-zA-Z0-9_-]+$/.test(row.name))) ||
      new Set(dexs.slice(1).map(row => row.name)).size !== dexs.length - 1 || states.length !== dexs.length) {
    throw new Error("invalid_portfolio");
  }
  const positions: Record<string, unknown>[] = [];
  const seen = new Set<string>();
  for (let index = 0; index < states.length; index++) {
    const state = states[index];
    if (!state || typeof state !== "object" || !Array.isArray((state as any).assetPositions) ||
        (state as any).assetPositions.length > 1000) throw new Error("invalid_portfolio");
    const dex = index === 0 ? "" : dexs[index].name as string;
    for (const row of (state as any).assetPositions) {
      const p = row?.position;
      if (row?.type !== "oneWay" || !p || typeof p.coin !== "string" || !coinPattern.test(p.coin) ||
          (dex ? !p.coin.startsWith(dex + ":") : p.coin.includes(":")) || seen.has(p.coin)) {
        throw new Error("invalid_portfolio");
      }
      seen.add(p.coin);
      const size = amount(p.szi);
      if (Number(size) === 0) continue;
      const valueUSD = amount(p.positionValue);
      const unrealizedPnLUSD = amount(p.unrealizedPnl);
      const returnOnEquity = amount(p.returnOnEquity);
      const entryPriceUSD = p.entryPx == null ? null : amount(p.entryPx);
      const leverage = p.leverage?.value;
      if (!Number.isSafeInteger(leverage) || leverage < 1 || leverage > 1000) throw new Error("invalid_portfolio");
      positions.push({ coin: p.coin, side: size.startsWith("-") ? "short" : "long", size,
        valueUSD, entryPriceUSD, unrealizedPnLUSD, returnOnEquity, leverage });
    }
  }
  if (positions.length > 1000 || !spot || typeof spot !== "object" || !Array.isArray((spot as any).balances) ||
      (spot as any).balances.length > 2048) throw new Error("invalid_portfolio");
  const cash = (spot as any).balances.find((row: any) => row?.coin === "USDC" && row?.token === 0);
  const spotUSDC = cash ? amount(cash.total) : "0";
  if (!Array.isArray(portfolio) || portfolio.length > 30) throw new Error("invalid_portfolio");
  const periods = new Map<string, { at: number; valueUSD: string }[]>();
  for (const row of portfolio) {
    if (!Array.isArray(row) || row.length !== 2 || typeof row[0] !== "string" ||
        !["perpDay", "perpWeek", "perpMonth"].includes(row[0])) continue;
    if (periods.has(row[0])) throw new Error("invalid_portfolio");
    periods.set(row[0], history(row[1]?.accountValueHistory));
  }
  const day = periods.get("perpDay") ?? [];
  const latest = day.at(-1);
  positions.sort((a, b) => Number(b.valueUSD) - Number(a.valueUSD));
  // Portfolio history is venue-reported; never add spot cash to it because unified
  // account mode can use that same collateral for perps.
  return { status: "ready", perpsEquityUSD: latest?.valueUSD ?? null,
    equityAsOf: latest?.at ?? null, spotUSDC, positions,
    history: { day, week: periods.get("perpWeek") ?? [], month: periods.get("perpMonth") ?? [] } };
}

export async function publicPortfolio(client: SupabaseClient, info: InfoReader, publicID: string) {
  const { data: profile, error: profileError } = await client.from("bsmart_feed_profiles")
    .select("account_id").eq("public_id", publicID).eq("visible", true).maybeSingle();
  if (profileError) throw new Error("profile_unavailable");
  if (!profile) return null;
  const { data: wallet, error: walletError } = await client.from("bsmart_wallets")
    .select("address").eq("account_id", profile.account_id).maybeSingle();
  if (walletError) throw new Error("wallet_unavailable");
  if (!wallet) return { status: "not_connected", perpsEquityUSD: null, equityAsOf: null,
    spotUSDC: null, positions: [], history: { day: [], week: [], month: [] } };
  if (typeof wallet.address !== "string" || !addressPattern.test(wallet.address)) throw new Error("invalid_wallet");
  const dexs = await info({ type: "perpDexs" });
  if (!Array.isArray(dexs) || dexs.length < 1 || dexs.length > 100) throw new Error("invalid_portfolio");
  const [states, spot, portfolio] = await Promise.all([
    Promise.all(dexs.map((row: any, index: number) => info({ type: "clearinghouseState", user: wallet.address,
      dex: index === 0 ? "" : row?.name }))),
    info({ type: "spotClearinghouseState", user: wallet.address }),
    info({ type: "portfolio", user: wallet.address }),
  ]);
  return parsePublicPortfolio(dexs, states, spot, portfolio);
}
