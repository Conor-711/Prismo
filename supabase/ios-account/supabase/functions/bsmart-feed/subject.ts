import type { Intent } from "./verification.ts";

export function subjectScope(url: URL) {
  const kind = url.searchParams.get("kind"), id = url.searchParams.get("id"), platform = url.searchParams.get("platform");
  if (!["account", "money"].includes(kind ?? "") || !id || id.length > 256 || id.trim() !== id ||
      /[\x00-\x1f\x7f]/.test(id) || !platform || platform.length > 32 || platform.trim() !== platform ||
      /[\x00-\x1f\x7f]/.test(platform) || (kind === "money" && platform !== "hyperliquid")) {
    throw new Error("invalid_input");
  }
  return { p_kind: kind, p_subject: id, p_platform: platform };
}

export function validCatalogSource(source: any, intent: Intent, now: number): boolean {
  if (source?.id?.toLowerCase() !== intent.opinionId || source.authorId !== intent.authorId ||
      source.ticker !== intent.ticker || !Number.isFinite(Date.parse(source.publishedAt)) ||
      Date.parse(source.publishedAt) > now) return false;
  if (source.sourceKind === "money") {
    return source.platform === "hyperliquid" && source.marketCoin === intent.coin &&
      source.platformPercentile === undefined;
  }
  return (source.sourceKind === undefined || source.sourceKind === "account") &&
    typeof source.platformPercentile === "number" && Number.isFinite(source.platformPercentile) &&
    source.platformPercentile >= 0 && source.platformPercentile <= 1;
}
