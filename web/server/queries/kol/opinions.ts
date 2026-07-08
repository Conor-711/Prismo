import type { Bi, KolOpinion } from "@/shared/market/mockDetail";
import { authorRefIdFor, isNoThesis, safe } from "./shared";
import {
  avatarMap,
  judgmentMap,
  qualityMap,
  refinedMap,
  relevanceMap,
  repliesByTweet,
  viewpointMap,
  ytChannelMap,
  ytDigestMap,
} from "./lookups";
import { redditOps, tossOps, xMergedOps, yahooJpOps, youtubeOps, xueqiuOps } from "./sources";

const COMPLETE_X_OPINION_LIMIT = 1_000_000;
export function getKolOpinions(symbol: string): KolOpinion[] {
  return safe(() => {
    const since = new Date(Date.now() - 370 * 864e5).toISOString().slice(0, 10);
    const raw = [
      ...redditOps(symbol, since, 200),
      ...youtubeOps(symbol, since, 80),
      ...xueqiuOps(symbol, since, 200),
      ...tossOps(symbol, since, 200),
      ...yahooJpOps(symbol, since, 200),
      ...xMergedOps(symbol, since, COMPLETE_X_OPINION_LIMIT),
    ];
    const refined = refinedMap(symbol);
    const vpMap = viewpointMap(symbol);
    const avatars = avatarMap();
    const relMap = relevanceMap(symbol);
    const qualMap = qualityMap();
    const repMap = repliesByTweet(symbol); // 仅 X：tweet_id -> 热门评论
    const ytChans = ytChannelMap(); // 仅 YouTube：channel_id -> 作者基础信息
    const ytDigests = ytDigestMap(); // 仅 YouTube：video_id -> 投资者摘要 + 目录
    const jMap = judgmentMap(symbol); // 目标价+周期（kol_judgment / yt_judgment；价格已剔噪）
    const out: KolOpinion[] = [];
    for (const r of raw) {
      if (!r.day) continue;
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
          if (r.source === "x" || stance === "neutral") stance = ref.stance;
        }
      }
      if (isNoThesis(reason)) continue;
      const hasReason = !!(reason && (reason.zh || reason.en));
      if (!hasReason && !r.zh && !r.en) continue;
      out.push({
        id: r.id,
        day: r.day,
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
        relevance: relMap.get(`${r.source}:${r.refKey}`) ?? r.relevance,
        quality: qualMap.get(`${r.source}:${r.refKey}`) ?? r.quality,
        metrics: r.source === "x" ? r.metrics : undefined,
        replies: r.source === "x" ? repMap.get(r.refKey) : undefined,
        ytSegments: r.source === "youtube" ? r.ytSegments : undefined,
        channel: r.source === "youtube" ? ytChans.get(r.avatarKey) : undefined,
        ytDigest: r.source === "youtube" ? ytDigests.get(r.refKey) : undefined,
        judgment: jMap.get(`${r.source}:${r.refKey}`) ?? r.judgment,
      });
    }
    return out;
  }, []);
}
