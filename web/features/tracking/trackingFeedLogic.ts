import type { KolSource } from "@/shared/market/mockDetail";
import {
  hasSubstantiveText,
  opinionAuthorRefId,
  qualOf,
  relOf,
  shiftDay,
} from "@/features/ticker/opinionExplorerLogic";
import type {
  TrackingFeedItem,
  TrackingFeedMode,
  TrackingRankedItem,
  TrackingRankReason,
  TrackingSourceFilter,
  TrackingStanceFilter,
} from "./trackingTypes";

const addReason = (reasons: TrackingRankReason[], reason: TrackingRankReason) => {
  if (!reasons.some((item) => item.zh === reason.zh)) reasons.push(reason);
};

const ageInDays = (day: string, maxDay: string) => {
  const current = Date.parse(`${day}T00:00:00Z`);
  const anchor = Date.parse(`${maxDay}T00:00:00Z`);
  if (!Number.isFinite(current) || !Number.isFinite(anchor)) return 365;
  return Math.max(0, Math.round((anchor - current) / 86_400_000));
};

function scoreItem(
  item: TrackingFeedItem,
  mode: TrackingFeedMode,
  maxDay: string,
  followedAuthors: Set<string>,
  followedNarrativeSymbols: Set<string>,
): TrackingRankedItem {
  const opinion = item.opinion;
  const quality = Math.max(0, qualOf(opinion));
  const relevance = Math.max(0, relOf(opinion));
  const age = ageInDays(opinion.day, maxDay);
  const recency = Math.max(0, 34 - age * 2.3);
  const engagement = Math.log1p(Math.max(0, opinion.interactions || 0)) * 2.4;
  const sv = item.svScore == null ? 0 : Math.max(0, Math.min(24, (item.svScore - 80) * 0.24));
  const actionable = opinion.judgment ? 16 : 0;
  const reasons: TrackingRankReason[] = [];
  const followedAuthor = followedAuthors.has(opinionAuthorRefId(opinion));
  const followedNarrative = followedNarrativeSymbols.has(item.symbol);

  let score = quality * 0.42 + relevance * 0.34 + engagement + recency + sv;
  if (mode === "latest") {
    score = Math.max(0, 400 - age * 48) + relevance * 0.35 + quality * 0.18 + engagement;
    addReason(reasons, { zh: age === 0 ? "今日新观点" : `${age} 天内更新`, en: age === 0 ? "Published today" : `Updated ${age}d ago` });
  } else if (mode === "quality") {
    score = quality * 0.58 + relevance * 0.38 + engagement + sv * 1.4 + (hasSubstantiveText(opinion) ? 16 : 0);
    addReason(reasons, { zh: "质量与相关度领先", en: "High quality and relevance" });
  } else if (mode === "changes") {
    score = quality * 0.28 + relevance * 0.28 + recency * 1.5 + sv * 1.5 + actionable * 2 + (opinion.stance !== "neutral" ? 10 : 0);
    if (opinion.judgment) addReason(reasons, { zh: "明确给出操作价位或周期", en: "Includes an actionable level or horizon" });
    else addReason(reasons, { zh: "近期高置信方向观点", en: "Recent high-conviction directional view" });
  } else {
    score += followedAuthor ? 28 : 0;
    score += followedNarrative ? 16 : 0;
    score += actionable;
    if (followedAuthor) addReason(reasons, { zh: "来自你追踪的作者", en: "From a followed author" });
    if (followedNarrative) addReason(reasons, { zh: "命中你追踪的叙事", en: "Matches a followed narrative" });
    if (!followedAuthor && !followedNarrative) addReason(reasons, { zh: "与你追踪的标的高度相关", en: "Highly relevant to a followed ticker" });
  }

  if (item.svPercentile != null && item.svPercentile <= 25) {
    score += mode === "latest" ? 5 : 12;
    addReason(reasons, { zh: "头部 Score 作者", en: "Top-quartile Score author" });
  }
  if (opinion.judgment && mode !== "changes") {
    addReason(reasons, { zh: "含明确价位或周期", en: "Includes a stated level or horizon" });
  }

  return { ...item, feedScore: score, reasons: reasons.slice(0, 2) };
}

function fairMerge(items: TrackingRankedItem[]): TrackingRankedItem[] {
  const sorted = [...items].sort((a, b) =>
    b.feedScore - a.feedScore ||
    b.opinion.day.localeCompare(a.opinion.day) ||
    b.opinion.interactions - a.opinion.interactions
  );
  const bySymbol = new Map<string, TrackingRankedItem[]>();
  for (const item of sorted) {
    const bucket = bySymbol.get(item.symbol);
    if (bucket) bucket.push(item);
    else bySymbol.set(item.symbol, [item]);
  }

  const symbols = [...bySymbol.keys()].sort((a, b) =>
    (bySymbol.get(b)?.[0]?.feedScore ?? 0) - (bySymbol.get(a)?.[0]?.feedScore ?? 0)
  );
  const fairCount = Math.min(sorted.length, Math.max(12, symbols.length * 3));
  const result: TrackingRankedItem[] = [];
  const used = new Set<string>();
  let round = 0;
  while (result.length < fairCount) {
    let added = false;
    for (const symbol of symbols) {
      const item = bySymbol.get(symbol)?.[round];
      if (!item) continue;
      result.push(item);
      used.add(`${item.symbol}:${item.opinion.source}:${item.opinion.id}`);
      added = true;
      if (result.length >= fairCount) break;
    }
    if (!added) break;
    round += 1;
  }
  for (const item of sorted) {
    const key = `${item.symbol}:${item.opinion.source}:${item.opinion.id}`;
    if (!used.has(key)) result.push(item);
  }
  return result;
}

export function rankTrackingFeed({
  items,
  mode,
  period,
  stance,
  source,
  symbol,
  followedAuthors,
  followedNarrativeSymbols,
}: {
  items: TrackingFeedItem[];
  mode: TrackingFeedMode;
  period: number;
  stance: TrackingStanceFilter;
  source: TrackingSourceFilter;
  symbol: string | null;
  followedAuthors: Set<string>;
  followedNarrativeSymbols: Set<string>;
}): TrackingRankedItem[] {
  const maxDay = items.reduce((max, item) => item.opinion.day > max ? item.opinion.day : max, "");
  if (!maxDay) return [];
  const since = shiftDay(maxDay, -(Math.max(1, period) - 1));
  const filtered = items.filter((item) => {
    if (item.opinion.day < since) return false;
    if (symbol && item.symbol !== symbol) return false;
    if (stance !== "all" && item.opinion.stance !== stance) return false;
    if (source !== "all" && item.opinion.source !== source) return false;
    return true;
  });
  return fairMerge(filtered.map((item) =>
    scoreItem(item, mode, maxDay, followedAuthors, followedNarrativeSymbols)
  ));
}

export function trackingSourceCounts(items: TrackingFeedItem[]): Partial<Record<KolSource, number>> {
  const counts: Partial<Record<KolSource, number>> = {};
  for (const item of items) counts[item.opinion.source] = (counts[item.opinion.source] ?? 0) + 1;
  return counts;
}
