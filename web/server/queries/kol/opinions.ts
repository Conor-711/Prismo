import type { Bi, KolOpinion } from "@/shared/market/mockDetail";
import { all } from "@/lib/db";
import { authorRefIdFor, isNoThesis, safe, type RawOp } from "./shared";
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
import { redditOps, tossOps, xMergedOps, yahooJpOps, youtubeOps, xueqiuOps, ytFulltextMap } from "./sources";

// OpinionExplorer is hydrated on the client, so its server payload must stay bounded.
// The database remains the full source of truth; these limits only shape the browsable pool.
const X_OPINION_LIMIT = 120;
// Apply the Reddit guard after recency ordering so the default one-month window wins
// over older high-engagement posts.
const REDDIT_OPINION_LIMIT = 350;
// The product only exposes the latest month of YouTube videos. Keep the whole
// monthly pool so engagement ranking cannot starve recent rows before filters run.
const YOUTUBE_OPINION_DAYS = 31;
const YOUTUBE_OPINION_LIMIT = 1_000;
// Toss can have thousands of posts per ticker/month. Keep the opinion feed broad
// enough for source-specific browsing while avoiding a five-figure client payload.
const LOCAL_OPINION_LIMIT = 100;
const X_COMPLETE_DAYS = 31;

function shiftUtcDay(day: string, offset: number): string {
  const date = new Date(`${day}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + offset);
  return date.toISOString().slice(0, 10);
}

function hydrateOpinions(symbol: string, raw: RawOp[], includeContent = true): KolOpinion[] {
  const refs = raw.map((op) => ({ source: op.source, itemId: op.refKey }));
  const refined = refinedMap(symbol, refs, includeContent);
  const vpMap = viewpointMap(symbol, refs);
  const avatars = avatarMap();
  const relMap = relevanceMap(symbol, refs);
  const qualMap = qualityMap(refs);
  const hasX = raw.some((op) => op.source === "x");
  const hasYoutube = raw.some((op) => op.source === "youtube");
  const repMap = hasX ? repliesByTweet(symbol) : new Map(); // 仅 X：tweet_id -> 热门评论
  const youtubeRows = hasYoutube ? raw.filter((op) => op.source === "youtube") : [];
  const ytChans = hasYoutube ? ytChannelMap(youtubeRows.map((op) => op.avatarKey)) : new Map(); // 仅 YouTube：channel_id -> 作者基础信息
  const ytDigests = hasYoutube ? ytDigestMap(youtubeRows.map((op) => op.refKey)) : new Map(); // 仅 YouTube：video_id -> 投资者摘要 + 内容目录
  const jMap = judgmentMap(symbol, refs); // 目标价+周期（kol_judgment / yt_judgment；价格已剔噪）
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
    const displayText = hasReason
      ? { zh: reason!.zh || reason!.en, en: reason!.en || reason!.zh }
      : { zh: r.zh || r.en, en: r.en || r.zh };
    out.push({
      id: r.id,
      day: r.day,
      source: r.source,
      author: r.author,
      authorRefId: authorRefIdFor(r.source, r.author, r.avatarKey),
      interactions: r.interactions,
      stance,
      // Full source/translation already live in orig/trans. Keeping text as the
      // concise thesis avoids serializing the same long body three times.
      text: displayText,
      orig: includeContent ? r.orig : undefined,
      trans: includeContent ? trans : undefined,
      quote: includeContent ? quote : undefined,
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
}

export function getKolOpinions(
  symbol: string,
  options: { includeContent?: boolean; preview?: boolean } = {}
): KolOpinion[] {
  return safe(() => {
    const measure = <T,>(label: string, load: () => T): T => {
      const startedAt = performance.now();
      const value = load();
      const elapsedMs = performance.now() - startedAt;
      if (process.env.NODE_ENV === "development" && elapsedMs >= 50) {
        console.info(`[ticker:${symbol}] opinions:${label} ${elapsedMs.toFixed(0)}ms`);
      }
      return value;
    };
    const includeContent = options.includeContent ?? false;
    const preview = options.preview ?? false;
    const since = new Date(Date.now() - 370 * 864e5).toISOString().slice(0, 10);
    const previewSince = new Date(Date.now() - 31 * 864e5).toISOString().slice(0, 10);
    const sourceSince = preview ? previewSince : since;
    const youtubeSince = new Date(Date.now() - YOUTUBE_OPINION_DAYS * 864e5).toISOString().slice(0, 10);
    const raw = [
      ...measure("reddit", () => redditOps(symbol, sourceSince, preview ? 36 : REDDIT_OPINION_LIMIT, includeContent)),
      ...measure("youtube", () => youtubeOps(symbol, youtubeSince, preview ? 24 : YOUTUBE_OPINION_LIMIT)),
      ...measure("xueqiu", () => xueqiuOps(symbol, sourceSince, preview ? 20 : LOCAL_OPINION_LIMIT, includeContent)),
      ...measure("toss", () => tossOps(symbol, sourceSince, preview ? 20 : LOCAL_OPINION_LIMIT, includeContent)),
      ...measure("yahoo", () => yahooJpOps(symbol, sourceSince, preview ? 20 : LOCAL_OPINION_LIMIT, includeContent)),
      ...measure("x", () => xMergedOps(symbol, sourceSince, preview ? 36 : X_OPINION_LIMIT, preview)),
    ];
    return measure("hydrate", () => hydrateOpinions(symbol, raw, includeContent));
  }, []);
}

export function getCompleteXOpinions(
  symbol: string,
  options: { includeContent?: boolean } = {}
): KolOpinion[] {
  return safe(() => {
    const latest = all<{ day: string | null }>(
      `SELECT MAX(substr(created,1,10)) AS day FROM x_opinion WHERE ticker = ?`,
      symbol
    )[0]?.day;
    if (!latest) return [];
    const since = shiftUtcDay(latest, -(X_COMPLETE_DAYS - 1));
    return hydrateOpinions(symbol, xMergedOps(symbol, since, null), options.includeContent ?? true);
  }, []);
}

export function getKolOpinionContent(symbol: string): Record<string, Pick<KolOpinion, "orig" | "trans" | "quote">> {
  const content: Record<string, Pick<KolOpinion, "orig" | "trans" | "quote">> = {};
  for (const opinion of getKolOpinions(symbol, { includeContent: true })) {
    if (opinion.source === "youtube") continue;
    content[opinion.id] = {
      orig: opinion.orig,
      trans: opinion.trans,
      quote: opinion.quote,
    };
  }
  return content;
}

export function getYoutubeOpinionContent(symbol: string): Record<string, Pick<KolOpinion, "orig" | "ytSegments">> {
  return safe(() => {
    const since = new Date(Date.now() - YOUTUBE_OPINION_DAYS * 864e5).toISOString().slice(0, 10);
    const content: Record<string, Pick<KolOpinion, "orig" | "ytSegments">> = {};
    for (const [videoId, fulltext] of ytFulltextMap(symbol, since, YOUTUBE_OPINION_LIMIT)) {
      content[`yt-${videoId}`] = {
        orig: fulltext.flat || undefined,
        ytSegments: fulltext.segments.length ? fulltext.segments : undefined,
      };
    }
    return content;
  }, {});
}
