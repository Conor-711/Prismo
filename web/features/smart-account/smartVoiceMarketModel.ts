import type { SmartVoiceMarketPlatformKey, SmartVoiceMarketSource, SmartVoiceMarketWindow, SmartVoiceTickerRank } from "@/server/queries/smartVoiceQueries";

export const MARKET_WINDOWS: SmartVoiceMarketWindow[] = ["24H", "3D", "7D", "30D", "90D"];

export const MARKET_SOURCES: { key: SmartVoiceMarketSource; label: string; color: string }[] = [
  { key: "x", label: "X", color: "#D7DCE2" },
  { key: "youtube", label: "YouTube", color: "#FF5C6C" },
  { key: "reddit", label: "Reddit", color: "#FF8A5B" },
  { key: "xueqiu", label: "雪球", color: "#5BA3C4" },
];

export const MODE_META = {
  newCoverage: { zh: "高 Score 新关注", en: "New high-Score coverage", color: "#8CBBFF" },
  bullish: { zh: "集中看多", en: "Bullish focus", color: "#57D7BA" },
  bearish: { zh: "集中看空", en: "Bearish focus", color: "#FF5C6C" },
  contrast: { zh: "高低 Score 分歧", en: "Score divergence", color: "#F7D14E" },
  authorShift: { zh: "作者净人数突变", en: "Author shifts", color: "#6EA8FE" },
} as const;

export type MarketMode = keyof typeof MODE_META;

export function signalLabel(signal: SmartVoiceTickerRank["signal"], zh: boolean) {
  const labels: Record<SmartVoiceTickerRank["signal"], [string, string]> = {
    high_bull_low_bear: ["高 Score 看多，低 Score 看空", "High-Score bull, low-Score bear"],
    high_bear_low_bull: ["高 Score 看空，低 Score 看多", "High-Score bear, low-Score bull"],
    sv_consensus_bull: ["高 Score 看多共识", "High-Score bullish consensus"],
    sv_consensus_bear: ["高 Score 看空共识", "High-Score bearish consensus"],
    mixed: ["观点仍有分歧", "Views remain mixed"],
  };
  return labels[signal][zh ? 0 : 1];
}

export function metricFor(row: SmartVoiceTickerRank, mode: MarketMode) {
  if (mode === "newCoverage") return row.newCoverageAuthorCount;
  if (mode === "bullish" || mode === "bearish") return row.highNet;
  if (mode === "authorShift") return row.authorNetShiftPct;
  return row.contrastScore;
}

export function highRatio(row: SmartVoiceTickerRank) {
  return row.highBullCalls + row.highBearCalls
    ? (row.highBullCalls / (row.highBullCalls + row.highBearCalls)) * 100
    : 50;
}

export function metricText(row: SmartVoiceTickerRank, mode: MarketMode) {
  const value = metricFor(row, mode);
  if (mode === "newCoverage") return `+${row.newCoverageAuthorCount}`;
  if (mode === "contrast") return `Δ${value.toFixed(1)}`;
  if (mode === "authorShift") return `${value > 0 ? "+" : ""}${value.toFixed(1)}%`;
  return `${value > 0 ? "+" : ""}${value.toFixed(1)}`;
}

export function metricColor(row: SmartVoiceTickerRank, mode: MarketMode) {
  if (mode === "newCoverage") return MODE_META.newCoverage.color;
  if (mode === "authorShift") return row.authorNetShiftPct >= 0 ? "#57D7BA" : "#FF5C6C";
  return MODE_META[mode].color;
}

export function signed(value: number) {
  return `${value > 0 ? "+" : ""}${value.toFixed(1)}`;
}

export function signedInteger(value: number) {
  return `${value > 0 ? "+" : ""}${value}`;
}

export function evidenceGroups(row: SmartVoiceTickerRank, mode: MarketMode) {
  if (mode === "newCoverage") {
    return row.newCoverageBullCount >= row.newCoverageBearCount
      ? { primary: row.evidenceIds.highBull, counter: row.evidenceIds.highBear }
      : { primary: row.evidenceIds.highBear, counter: row.evidenceIds.highBull };
  }
  if (mode === "bullish") return { primary: row.evidenceIds.highBull, counter: row.evidenceIds.highBear };
  if (mode === "bearish") return { primary: row.evidenceIds.highBear, counter: row.evidenceIds.highBull };
  if (mode === "authorShift") {
    const current = row.highAuthorNet > 0
      ? row.evidenceIds.highBull
      : row.highAuthorNet < 0
        ? row.evidenceIds.highBear
        : [...row.evidenceIds.highBull, ...row.evidenceIds.highBear];
    const previous = row.previousHighAuthorNet > 0
      ? row.evidenceIds.previousHighBull
      : row.previousHighAuthorNet < 0
        ? row.evidenceIds.previousHighBear
        : [...row.evidenceIds.previousHighBull, ...row.evidenceIds.previousHighBear];
    return { primary: current, counter: previous };
  }
  if (row.highNet >= 0) return { primary: row.evidenceIds.highBull, counter: row.evidenceIds.lowBear };
  return { primary: row.evidenceIds.highBear, counter: row.evidenceIds.lowBull };
}

export function platformKeyOf(sources: SmartVoiceMarketSource[]): SmartVoiceMarketPlatformKey {
  if (sources.length === MARKET_SOURCES.length) return "all";
  const selected = new Set(sources);
  return MARKET_SOURCES.map((item) => item.key)
    .filter((source) => selected.has(source))
    .join("+") as SmartVoiceMarketPlatformKey;
}
