import type { Bi, KolFlow, KolOpinion } from "@/shared/market/mockDetail";
import { authorRefIdFor, isNoThesis, priceDays, snapToTradingDay } from "./shared";
import { avatarMap, refinedMap, viewpointMap } from "./lookups";
import { redditOps, tossOps, xMergedOps, yahooJpOps, youtubeOps, xueqiuOps } from "./sources";

export function getKolFlowReal(symbol: string): KolFlow | null {
  const days = priceDays(symbol);
  if (days.length < 4) return null; // 价格历史不足 → 回退 mock
  const tradingDays = days.map((d) => d.day);
  const since = tradingDays[0];

  const raw = [
    ...redditOps(symbol, since),
    ...youtubeOps(symbol, since),
    ...xueqiuOps(symbol, since),
    ...tossOps(symbol, since),
    ...yahooJpOps(symbol, since),
    ...xMergedOps(symbol, since),
  ];
  const refined = refinedMap(symbol);
  const vpMap = viewpointMap(symbol);
  const avatars = avatarMap();
  const opinions: KolOpinion[] = [];
  for (const r of raw) {
    const day = snapToTradingDay(r.day, tradingDays);
    if (!day) continue;

    // 提炼结果：YouTube 已在 youtubeOps 里带上（yt_analysis）；其余源 join kol_refined。
    let reason = r.reason;
    let points = r.points;
    let stance = r.stance;
    let trans: Bi | undefined;
    let quote: Bi | undefined;
    if (r.source !== "youtube") {
      const ref = refined.get(`${r.source}:${r.refKey}`);
      if (ref) {
        reason = ref.reason;
        points = ref.points;
        trans = ref.trans && (ref.trans.zh || ref.trans.en) ? ref.trans : undefined;
        quote = ref.quote && (ref.quote.zh || ref.quote.en) ? ref.quote : undefined;
        // X 无原生情绪 → 用提炼立场；reddit/雪球 原生中性时也用提炼立场补足
        if (r.source === "x" || stance === "neutral") stance = ref.stance;
      }
    }
    // 提炼后判定为「无明确观点」（新闻转述/过度匹配标的）→ 不当作 KOL 观点展示
    if (isNoThesis(reason)) continue;
    const hasReason = !!(reason && (reason.zh || reason.en));
    if (!hasReason && !r.zh && !r.en) continue; // 既无提炼也无原文 → 丢弃

    opinions.push({
      id: r.id,
      day,
      source: r.source,
      author: r.author,
      authorRefId: authorRefIdFor(r.source, r.author, r.avatarKey),
      interactions: r.interactions,
      stance,
      text: { zh: r.zh || r.en, en: r.en || r.zh },
      orig: r.orig,
      trans,
      quote,
      reason: hasReason ? { zh: reason!.zh || reason!.en, en: reason!.en || reason!.zh } : undefined,
      points: points && (points.zh.length || points.en.length) ? points : undefined,
      url: r.url,
      avatar:
        avatars.get(`${r.source}:${r.avatarKey}`) ||
        (r.source === "x" && r.avatarKey ? `https://unavatar.io/twitter/${r.avatarKey}` : undefined),
      viewpoints: vpMap.get(`${r.source}:${r.refKey}`),
      relevance: r.relevance,
      quality: r.quality,
      judgment: r.judgment,
    });
  }
  if (!opinions.length) return null;
  return { days, opinions };
}
