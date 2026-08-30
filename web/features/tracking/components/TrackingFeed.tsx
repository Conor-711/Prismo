"use client";

import { useMemo } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Avatar, mmdd, pickOriginal, SOURCE, STANCE } from "@/shared/market/kolPresentation";
import { TickerLogo } from "@/shared/market/TickerLogo";
import type { Stance } from "@/shared/market/mockDetail";
import type { GrTickerRow } from "@/server/queries/globalQueries";
import type { TrackingFeedItem, TrackingRankedItem } from "../trackingTypes";

export function trackingFeedItemKey(item: TrackingFeedItem) {
  return `${item.symbol}:${item.opinion.source}:${item.opinion.id}`;
}

export function TrackingFeedList({
  zh,
  items,
  busy,
  partialError,
  hasTrackedTickers,
  selectedKey,
  onSelect,
}: {
  zh: boolean;
  items: TrackingRankedItem[];
  busy: boolean;
  partialError: boolean;
  hasTrackedTickers: boolean;
  selectedKey: string;
  onSelect: (item: TrackingRankedItem) => void;
}) {
  if (busy) {
    return <div className="grid min-h-0 flex-1 place-items-center text-[11.5px] text-neutral-600">{zh ? "正在生成个性化观点流…" : "Building your personalized feed…"}</div>;
  }
  if (!hasTrackedTickers) {
    return (
      <div className="grid min-h-0 flex-1 place-items-center px-8 text-center">
        <div>
          <div className="mx-auto grid h-10 w-10 place-items-center rounded-full bg-reddit/10 text-reddit ring-1 ring-inset ring-reddit/35">＋</div>
          <h3 className="mt-3 text-[13px] font-bold text-cream">{zh ? "先追踪一个标的" : "Follow a ticker first"}</h3>
          <p className="mt-1 max-w-[250px] text-[11px] leading-relaxed text-neutral-600">
            {zh ? "从顶部搜索框添加标的，最新且最值得看的观点会自动进入这里。" : "Add a ticker above and its latest, highest-value views will appear here."}
          </p>
        </div>
      </div>
    );
  }
  if (items.length === 0) {
    return <div className="grid min-h-0 flex-1 place-items-center text-[11.5px] text-neutral-600">{zh ? "当前筛选下没有观点" : "No opinions match these filters"}</div>;
  }
  return (
    <div className="min-h-0 flex-1 overflow-y-auto">
      {partialError && (
        <div className="border-b border-line bg-bear/5 px-3 py-1.5 text-[10px] text-bear">
          {zh ? "部分标的数据暂未载入，已展示其余结果。" : "Some ticker data could not load; showing the rest."}
        </div>
      )}
      {items.map((item) => {
        const active = selectedKey === trackingFeedItemKey(item);
        const sourceMeta = SOURCE[item.opinion.source];
        const stanceMeta = STANCE[item.opinion.stance];
        const { base, trans, canTranslate } = pickOriginal(item.opinion, zh);
        const text = canTranslate ? trans : base;
        return (
          <button
            key={trackingFeedItemKey(item)}
            type="button"
            onClick={() => onSelect(item)}
            className={`relative block w-full border-b border-line px-3 py-3 text-left transition ${
              active ? "bg-reddit/[.07]" : "hover:bg-white/[.025]"
            }`}
          >
            <span className="absolute inset-y-0 left-0 w-[3px]" style={{ background: active ? "#57D7BA" : stanceMeta.color }} />
            <span className="flex items-center gap-2">
              <TickerLogo ticker={item.symbol} size={22} />
              <span className="font-mono text-[11.5px] font-bold text-cream">{item.symbol}</span>
              <span className="h-3 w-px bg-line" />
              <span className="min-w-0 flex-1 truncate text-[11px] font-medium text-neutral-300">{item.opinion.author}</span>
              <span className="shrink-0 text-[9.5px] text-neutral-600">{mmdd(item.opinion.day)}</span>
            </span>
            <span className="mt-2 block line-clamp-3 text-[11.5px] leading-[1.5] text-neutral-400">{text || (zh ? "暂无正文预览" : "No preview")}</span>
            <span className="mt-2 flex items-center gap-1.5">
              <span className="rounded px-1.5 py-0.5 text-[9.5px] ring-1 ring-inset ring-line" style={{ color: sourceMeta.color }}>{sourceMeta.label}</span>
              <span className="text-[9.5px] font-semibold" style={{ color: stanceMeta.color }}>{zh ? stanceMeta.zh : stanceMeta.en}</span>
              {item.svScore != null && <span className="font-mono text-[9.5px] text-reddit">Score {Math.round(item.svScore)}</span>}
              <span className="font-mono text-[9.5px] text-neutral-600">Q {item.opinion.quality ?? "—"} · R {item.opinion.relevance ?? "—"}</span>
              {item.reasons[0] && <span className="ml-auto max-w-[130px] truncate text-[9.5px] text-neutral-600">{zh ? item.reasons[0].zh : item.reasons[0].en}</span>}
            </span>
          </button>
        );
      })}
    </div>
  );
}

export function TrackingOverview({
  zh,
  items,
  allItems,
  trackedSymbols,
  rowMap,
  onSelect,
}: {
  zh: boolean;
  items: TrackingRankedItem[];
  allItems: TrackingFeedItem[];
  trackedSymbols: string[];
  rowMap: Map<string, GrTickerRow>;
  onSelect: (item: TrackingRankedItem) => void;
}) {
  const stanceCounts = allItems.reduce((counts, item) => {
    counts[item.opinion.stance] += 1;
    return counts;
  }, { bull: 0, neutral: 0, bear: 0 } as Record<Stance, number>);
  const stanceTotal = Math.max(1, stanceCounts.bull + stanceCounts.neutral + stanceCounts.bear);
  const topVoices = useMemo(() => {
    const byAuthor = new Map<string, TrackingFeedItem>();
    for (const item of allItems) {
      if (item.svScore == null) continue;
      const key = `${item.opinion.source}:${item.opinion.authorRefId ?? item.opinion.author}`;
      const current = byAuthor.get(key);
      if (!current || (item.svScore ?? 0) > (current.svScore ?? 0)) byAuthor.set(key, item);
    }
    return [...byAuthor.values()].sort((a, b) => (b.svScore ?? 0) - (a.svScore ?? 0)).slice(0, 4);
  }, [allItems]);

  return (
    <section className="flex h-full min-h-0 flex-col overflow-hidden rounded-md bg-card/30 ring-1 ring-inset ring-line">
      <div className="shrink-0 border-b border-line px-4 py-3">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h2 className="text-[14px] font-bold text-cream">{zh ? "追踪组合概览" : "Watchlist overview"}</h2>
            <p className="mt-0.5 text-[10.5px] text-neutral-600">{zh ? "先看组合变化，再进入单条观点" : "Scan the watchlist, then open any opinion"}</p>
          </div>
          <div className="grid grid-cols-3 gap-5 text-right">
            <OverviewStat label={zh ? "标的" : "Tickers"} value={trackedSymbols.length} />
            <OverviewStat label={zh ? "观点" : "Views"} value={allItems.length} />
            <OverviewStat label={zh ? "头部Score" : "Top Score"} value={topVoices.length} accent />
          </div>
        </div>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto px-4 py-3">
        <div className="grid grid-cols-[minmax(0,1.25fr)_minmax(240px,.75fr)] gap-5">
          <div className="min-w-0">
            <SectionTitle title={zh ? "当前情绪结构" : "Current stance mix"} />
            <div className="mt-2 flex h-2 overflow-hidden rounded-full bg-elevated">
              <span style={{ width: `${(stanceCounts.bull / stanceTotal) * 100}%`, background: STANCE.bull.color }} />
              <span style={{ width: `${(stanceCounts.neutral / stanceTotal) * 100}%`, background: STANCE.neutral.color }} />
              <span style={{ width: `${(stanceCounts.bear / stanceTotal) * 100}%`, background: STANCE.bear.color }} />
            </div>
            <div className="mt-2 grid grid-cols-3 gap-2">
              {(["bull", "neutral", "bear"] as Stance[]).map((value) => (
                <div key={value}>
                  <div className="text-[9.5px] text-neutral-600">{zh ? STANCE[value].zh : STANCE[value].en}</div>
                  <div className="mt-0.5 font-mono text-[12px] font-bold" style={{ color: STANCE[value].color }}>
                    {Math.round((stanceCounts[value] / stanceTotal) * 100)}%
                  </div>
                </div>
              ))}
            </div>

            <SectionTitle title={zh ? "优先阅读" : "Read first"} className="mt-6" />
            <div className="mt-1 divide-y divide-line">
              {items.slice(0, 5).map((item, index) => (
                <button
                  key={trackingFeedItemKey(item)}
                  type="button"
                  onClick={() => onSelect(item)}
                  className="flex w-full items-center gap-2 py-2.5 text-left hover:bg-white/[.02]"
                >
                  <span className="w-4 shrink-0 font-mono text-[9.5px] text-neutral-700">{String(index + 1).padStart(2, "0")}</span>
                  <TickerLogo ticker={item.symbol} size={22} />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[11px] font-semibold text-neutral-200">{item.symbol} · {item.opinion.author}</span>
                    <span className="mt-0.5 block truncate text-[9.5px] text-neutral-600">{zh ? item.reasons[0]?.zh : item.reasons[0]?.en}</span>
                  </span>
                  <span className="text-[10px] font-semibold" style={{ color: STANCE[item.opinion.stance].color }}>
                    {zh ? STANCE[item.opinion.stance].zh : STANCE[item.opinion.stance].en}
                  </span>
                </button>
              ))}
              {items.length === 0 && <div className="py-6 text-[11px] text-neutral-600">{zh ? "暂无可展示观点" : "No views to show"}</div>}
            </div>
          </div>

          <div className="min-w-0 border-l border-line pl-5">
            <SectionTitle title="Smart Account" />
            <p className="mt-1 text-[9.5px] leading-relaxed text-neutral-600">
              {zh ? "当前追踪组合中已进入 Score 评分池的头部作者。" : "Top scored voices represented in the current watchlist."}
            </p>
            <div className="mt-2 divide-y divide-line">
              {topVoices.map((item, index) => (
                <div key={`${item.opinion.source}:${item.opinion.author}`} className="flex items-center gap-2 py-2.5">
                  <span className="w-4 font-mono text-[9px] text-neutral-700">#{index + 1}</span>
                  <Avatar src={item.opinion.avatar} color={SOURCE[item.opinion.source].color} name={item.opinion.author} size={24} />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-[10.5px] font-semibold text-neutral-300">{item.opinion.author}</div>
                    <div className="mt-0.5 text-[9px] text-neutral-600">{SOURCE[item.opinion.source].label} · {item.symbol}</div>
                  </div>
                  <span className="font-mono text-[12px] font-bold text-reddit">{Math.round(item.svScore ?? 0)}</span>
                </div>
              ))}
              {topVoices.length === 0 && <div className="py-5 text-[10px] text-neutral-600">{zh ? "当前观点暂无 Score 匹配" : "No Score matches in the current feed"}</div>}
            </div>

            <SectionTitle title={zh ? "标的状态" : "Ticker status"} className="mt-5" />
            <div className="mt-1 divide-y divide-line">
              {trackedSymbols.slice(0, 6).map((symbol) => {
                const row = rowMap.get(symbol);
                return (
                  <LocaleLink key={symbol} href={`/tickers/${symbol}`} className="flex items-center gap-2 py-2 hover:text-reddit">
                    <TickerLogo ticker={symbol} size={20} />
                    <span className="font-mono text-[10.5px] font-bold text-neutral-300">{symbol}</span>
                    <span className="ml-auto font-mono text-[10px]" style={{ color: (row?.avg_sentiment ?? 0) >= 0 ? STANCE.bull.color : STANCE.bear.color }}>
                      {row ? `${row.avg_sentiment >= 0 ? "+" : ""}${row.avg_sentiment.toFixed(2)}` : "—"}
                    </span>
                  </LocaleLink>
                );
              })}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function OverviewStat({ label, value, accent = false }: { label: string; value: number; accent?: boolean }) {
  return (
    <div>
      <div className="text-[9px] uppercase text-neutral-600">{label}</div>
      <div className={`mt-0.5 font-mono text-[14px] font-bold ${accent ? "text-reddit" : "text-neutral-200"}`}>{value}</div>
    </div>
  );
}

function SectionTitle({ title, className = "" }: { title: string; className?: string }) {
  return <h3 className={`text-[10.5px] font-bold uppercase text-neutral-400 ${className}`}>{title}</h3>;
}
