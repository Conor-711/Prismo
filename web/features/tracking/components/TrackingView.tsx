"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useFavorites } from "@/components/favorites/FavoritesProvider";
import { Reader } from "@/features/ticker/components/OpinionExplorer/reader";
import {
  listLocalTrackingCollection,
  type CollectionRow,
} from "@/lib/favorites";
import { staticDataUrl } from "@/lib/site";
import { withLang, type Locale } from "@/lib/i18n";
import { fmtCompact } from "@/shared/formatting/format";
import { SOURCE, SOURCE_ORDER } from "@/shared/market/kolPresentation";
import type { GrTickerRow } from "@/server/queries/globalQueries";
import type { KolOpinion } from "@/shared/market/mockDetail";
import { rankTrackingFeed, trackingSourceCounts } from "../trackingFeedLogic";
import {
  emptyCollections,
  type QuickCandidate,
  type TrackKind,
  type TrackingCatalog,
  type TrackingFeedItem,
  type TrackingFeedMode,
  type TrackingPeriod,
  type TrackingRankedItem,
  type TrackingSourceFilter,
  type TrackingStanceFilter,
} from "../trackingTypes";
import { QuickAdd } from "./trackingCards";
import { TrackingFeedList, TrackingOverview, trackingFeedItemKey } from "./TrackingFeed";
import { TrackingRail } from "./TrackingRail";

const MODE_OPTIONS: { id: TrackingFeedMode; zh: string; en: string }[] = [
  { id: "personal", zh: "为你推荐", en: "For You" },
  { id: "latest", zh: "最新", en: "Latest" },
  { id: "quality", zh: "高质量", en: "Quality" },
  { id: "changes", zh: "重要变化", en: "Important" },
];
const PERIOD_OPTIONS: TrackingPeriod[] = [1, 3, 7, 30];

export function TrackingView({
  rows,
  catalog,
  lang,
}: {
  rows: GrTickerRow[];
  catalog: TrackingCatalog;
  lang: Locale;
}) {
  const zh = lang === "zh";
  const router = useRouter();
  const { ready, version, isSaved, toggle } = useFavorites();
  const [collections, setCollections] = useState<Record<TrackKind, CollectionRow[]>>(emptyCollections);
  const [collectionsBusy, setCollectionsBusy] = useState(true);
  const [query, setQuery] = useState("");
  const [mode, setMode] = useState<TrackingFeedMode>("personal");
  const [period, setPeriod] = useState<TrackingPeriod>(7);
  const [stance, setStance] = useState<TrackingStanceFilter>("all");
  const [source, setSource] = useState<TrackingSourceFilter>("all");
  const [symbolFilter, setSymbolFilter] = useState<string | null>(null);
  const [feedItems, setFeedItems] = useState<TrackingFeedItem[]>([]);
  const [feedBusy, setFeedBusy] = useState(false);
  const [feedError, setFeedError] = useState(false);
  const [selected, setSelected] = useState<TrackingRankedItem | null>(null);
  const [showOriginal, setShowOriginal] = useState(false);
  const [contentByKey, setContentByKey] = useState<Record<string, Partial<KolOpinion>>>({});

  useEffect(() => {
    if (!ready) return;
    setCollections({
      ticker: listLocalTrackingCollection("ticker"),
      author: listLocalTrackingCollection("author"),
      narrative: listLocalTrackingCollection("narrative"),
    });
    setCollectionsBusy(false);
  }, [ready, version]);

  const rowMap = useMemo(() => {
    const map = new Map<string, GrTickerRow>();
    for (const row of rows) map.set(row.ticker.toUpperCase(), row);
    return map;
  }, [rows]);
  const authorMap = useMemo(() => new Map(catalog.authors.map((author) => [author.refId, author])), [catalog.authors]);
  const narrativeMap = useMemo(() => new Map(catalog.narratives.map((narrative) => [narrative.refId, narrative])), [catalog.narratives]);
  const trackedSymbols = useMemo(
    () => collections.ticker.map((row) => row.ref_id.toUpperCase()),
    [collections.ticker],
  );
  const symbolKey = trackedSymbols.join(",");

  useEffect(() => {
    if (!ready || trackedSymbols.length === 0) {
      setFeedItems([]);
      setFeedBusy(false);
      return;
    }
    const controller = new AbortController();
    setFeedBusy(true);
    setFeedError(false);
    Promise.allSettled(
      trackedSymbols.map((symbol) =>
        fetch(staticDataUrl(`/data/tracking-feed/${encodeURIComponent(symbol)}`), { signal: controller.signal })
          .then((response) => {
            if (!response.ok) throw new Error(`Tracking feed export returned ${response.status}`);
            return response.json() as Promise<{ items?: TrackingFeedItem[] }>;
          })
      ),
    ).then((results) => {
      if (controller.signal.aborted) return;
      const next = results.flatMap((result) =>
        result.status === "fulfilled" && Array.isArray(result.value.items)
          ? result.value.items
          : []
      );
      setFeedItems(next);
      setFeedError(results.some((result) => result.status === "rejected"));
      setFeedBusy(false);
    });
    return () => controller.abort();
  // symbolKey is the stable dependency; trackedSymbols is intentionally derived from it.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, symbolKey]);

  useEffect(() => {
    if (symbolFilter && !trackedSymbols.includes(symbolFilter)) setSymbolFilter(null);
    if (selected && !trackedSymbols.includes(selected.symbol)) setSelected(null);
  }, [selected, symbolFilter, trackedSymbols]);

  const followedAuthors = useMemo(
    () => new Set(collections.author.map((row) => row.ref_id)),
    [collections.author],
  );
  const followedNarrativeSymbols = useMemo(() => {
    const symbols = new Set<string>();
    for (const row of collections.narrative) {
      for (const ticker of narrativeMap.get(row.ref_id)?.tickers ?? []) symbols.add(ticker);
    }
    return symbols;
  }, [collections.narrative, narrativeMap]);
  const ranked = useMemo(
    () => rankTrackingFeed({
      items: feedItems,
      mode,
      period,
      stance,
      source,
      symbol: symbolFilter,
      followedAuthors,
      followedNarrativeSymbols,
    }),
    [feedItems, followedAuthors, followedNarrativeSymbols, mode, period, source, stance, symbolFilter],
  );
  const sourceCounts = useMemo(() => trackingSourceCounts(feedItems), [feedItems]);
  const availableSources = useMemo(
    () => SOURCE_ORDER.filter((item) => (sourceCounts[item] ?? 0) > 0),
    [sourceCounts],
  );

  const quickCandidates = useMemo(() => {
    const tickerItems: QuickCandidate[] = rows.slice(0, 100).map((row) => ({
      kind: "ticker",
      refId: row.ticker.toUpperCase(),
      label: `${row.ticker.toUpperCase()} · ${zh ? row.name_zh || row.name_en : row.name_en || row.name_zh}`,
      sub: `${fmtCompact(row.total_posts)} ${zh ? "讨论" : "posts"} · ${zh ? "情绪" : "sentiment"} ${row.avg_sentiment > 0 ? "+" : ""}${row.avg_sentiment.toFixed(2)}`,
      href: `/tickers/${row.ticker.toUpperCase()}`,
      ticker: row.ticker.toUpperCase(),
    }));
    const authorItems: QuickCandidate[] = catalog.authors.slice(0, 100).map((author) => ({
      kind: "author",
      refId: author.refId,
      label: author.name,
      sub: `${author.source} · ${fmtCompact(author.metric)} ${author.source === "YouTube" ? (zh ? "播放" : "views") : (zh ? "互动" : "interactions")}`,
      href: author.href,
      url: author.url,
      avatar: author.avatar,
    }));
    const narrativeItems: QuickCandidate[] = catalog.narratives.map((narrative) => ({
      kind: "narrative",
      refId: narrative.refId,
      label: zh ? narrative.titleZh : narrative.titleEn,
      sub: `${narrative.rank ? `#${narrative.rank} · ` : ""}${(narrative.share * 100).toFixed(1)}% · ${zh ? narrative.trendZh : narrative.trendEn}`,
      href: `/narratives/${narrative.refId}`,
      color: narrative.color,
    }));
    const needle = query.trim().toLowerCase();
    return [...tickerItems, ...authorItems, ...narrativeItems]
      .filter((candidate) => !needle || `${candidate.label} ${candidate.sub} ${candidate.refId}`.toLowerCase().includes(needle))
      .sort((a, b) => Number(isSaved(a.kind, a.refId)) - Number(isSaved(b.kind, b.refId)))
      .slice(0, needle ? 12 : 10);
  }, [catalog, isSaved, query, rows, zh]);

  const selectedKey = selected ? trackingFeedItemKey(selected) : "";
  const selectedOpinion = selected
    ? { ...selected.opinion, ...(contentByKey[selectedKey] ?? {}) }
    : null;
  useEffect(() => {
    if (!selected || !selectedKey || contentByKey[selectedKey]) return;
    const isYoutube = selected.opinion.source === "youtube";
    if (isYoutube && selected.opinion.ytSegments?.length) return;
    if (!isYoutube && (selected.opinion.orig || selected.opinion.trans || selected.opinion.quote)) return;
    const controller = new AbortController();
    const path = isYoutube ? "youtube-content" : "opinion-content";
    fetch(staticDataUrl(`/data/${path}/${encodeURIComponent(selected.symbol)}`), { signal: controller.signal })
      .then((response) => {
        if (!response.ok) throw new Error(`Opinion content export returned ${response.status}`);
        return response.json();
      })
      .then((payload: { content?: Record<string, Partial<KolOpinion>> }) => {
        const content = payload.content?.[selected.opinion.id] ?? {};
        setContentByKey((current) => ({ ...current, [selectedKey]: content }));
      })
      .catch((error: unknown) => {
        if (!(error instanceof DOMException && error.name === "AbortError")) {
          console.error("Failed to load tracked opinion content", error);
          setContentByKey((current) => ({ ...current, [selectedKey]: {} }));
        }
      });
    return () => controller.abort();
  }, [contentByKey, selected, selectedKey]);

  const removeTracking = (kind: TrackKind, refId: string) => {
    void toggle(kind, refId);
  };

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-2.5">
      <div className="flex shrink-0 items-center gap-2.5">
        <div className="min-w-0 max-w-[460px] flex-1">
          <QuickAdd
            zh={zh}
            query={query}
            setQuery={setQuery}
            candidates={quickCandidates}
            onSeeAll={() => router.push(withLang(lang, "/tickers"))}
          />
        </div>
        <div className="flex h-9 shrink-0 items-center rounded-md bg-card/55 p-0.5 ring-1 ring-inset ring-line">
          {MODE_OPTIONS.map((option) => (
            <button
              key={option.id}
              type="button"
              onClick={() => { setMode(option.id); setSelected(null); }}
              aria-pressed={mode === option.id}
              className={`h-8 rounded px-3 text-[11.5px] font-semibold transition ${
                mode === option.id ? "bg-reddit/15 text-reddit ring-1 ring-inset ring-reddit/45" : "text-neutral-500 hover:text-neutral-200"
              }`}
            >
              {zh ? option.zh : option.en}
            </button>
          ))}
        </div>
        <span className="ml-auto shrink-0 font-mono text-[10.5px] text-neutral-600">
          {feedItems.length ? `${ranked.length}/${feedItems.length}` : ""}
        </span>
      </div>

      <div className="grid min-h-0 flex-1 grid-cols-[190px_340px_minmax(0,1fr)] gap-2.5 overflow-hidden xl:grid-cols-[210px_390px_minmax(0,1fr)]">
        <TrackingRail
          zh={zh}
          busy={collectionsBusy}
          collections={collections}
          rowMap={rowMap}
          authorMap={authorMap}
          narrativeMap={narrativeMap}
          selectedSymbol={symbolFilter}
          onSelectSymbol={setSymbolFilter}
          onRemove={removeTracking}
        />

        <section className="flex min-h-0 flex-col overflow-hidden rounded-md bg-card/40 ring-1 ring-inset ring-line">
          <div className="shrink-0 border-b border-line px-3 py-2.5">
            <div className="flex items-center justify-between gap-2">
              <div>
                <h2 className="text-[12.5px] font-bold text-cream">{zh ? "观点流" : "Opinion feed"}</h2>
                <p className="mt-0.5 text-[10px] text-neutral-600">
                  {symbolFilter ?? (zh ? `${trackedSymbols.length} 个追踪标的公平合并` : `Fair merge across ${trackedSymbols.length} tickers`)}
                </p>
              </div>
              <div className="flex rounded bg-ink/60 p-0.5 ring-1 ring-inset ring-line">
                {PERIOD_OPTIONS.map((days) => (
                  <button
                    key={days}
                    type="button"
                    onClick={() => { setPeriod(days); setSelected(null); }}
                    className={`h-6 min-w-8 rounded px-1.5 text-[10.5px] font-semibold transition ${
                      period === days ? "bg-reddit/15 text-reddit ring-1 ring-inset ring-reddit/40" : "text-neutral-600 hover:text-neutral-300"
                    }`}
                  >
                    {days === 30 ? (zh ? "1月" : "30D") : `${days}D`}
                  </button>
                ))}
              </div>
            </div>
            <div className="mt-2 flex items-center gap-1.5">
              <FilterSelect
                value={stance}
                onChange={(value) => { setStance(value as TrackingStanceFilter); setSelected(null); }}
                ariaLabel={zh ? "情绪筛选" : "Stance filter"}
                options={[
                  ["all", zh ? "全部情绪" : "All stances"],
                  ["bull", zh ? "看多" : "Bull"],
                  ["neutral", zh ? "中性" : "Neutral"],
                  ["bear", zh ? "看空" : "Bear"],
                ]}
              />
              <FilterSelect
                value={source}
                onChange={(value) => { setSource(value as TrackingSourceFilter); setSelected(null); }}
                ariaLabel={zh ? "平台筛选" : "Source filter"}
                options={[
                  ["all", zh ? "全部平台" : "All sources"],
                  ...availableSources.map((item) => [item, `${SOURCE[item].label} ${sourceCounts[item] ?? 0}`] as [string, string]),
                ]}
              />
              {(stance !== "all" || source !== "all" || symbolFilter) && (
                <button
                  type="button"
                  onClick={() => { setStance("all"); setSource("all"); setSymbolFilter(null); setSelected(null); }}
                  className="ml-auto text-[10.5px] font-medium text-reddit hover:text-reddit/80"
                >
                  {zh ? "清除" : "Clear"}
                </button>
              )}
            </div>
          </div>

          <TrackingFeedList
            zh={zh}
            items={ranked}
            busy={feedBusy || collectionsBusy}
            partialError={feedError}
            hasTrackedTickers={trackedSymbols.length > 0}
            selectedKey={selectedKey}
            onSelect={(item) => {
              setSelected(item);
              setShowOriginal(false);
            }}
          />
        </section>

        <div className="min-h-0 min-w-0 overflow-hidden">
          {selected && selectedOpinion ? (
            <Reader
              o={selectedOpinion}
              zh={zh}
              showT={showOriginal}
              setShowT={setShowOriginal}
              fill
              recReasons={selected.reasons}
              svRank={selected.svScore != null && selected.svRank != null ? {
                rank: selected.svRank,
                count: selected.svPopulation ?? selected.svRank,
                percentile: selected.svPercentile ?? 100,
                score: selected.svScore,
              } : undefined}
              onBack={() => setSelected(null)}
            />
          ) : (
            <TrackingOverview
              zh={zh}
              items={ranked}
              allItems={feedItems}
              trackedSymbols={trackedSymbols}
              rowMap={rowMap}
              onSelect={setSelected}
            />
          )}
        </div>
      </div>
    </div>
  );
}

function FilterSelect({
  value,
  onChange,
  ariaLabel,
  options,
}: {
  value: string;
  onChange: (value: string) => void;
  ariaLabel: string;
  options: [string, string][];
}) {
  return (
    <select
      value={value}
      onChange={(event) => onChange(event.target.value)}
      aria-label={ariaLabel}
      className="h-7 min-w-0 rounded bg-ink/55 px-2 text-[10.5px] text-neutral-400 ring-1 ring-inset ring-line outline-none focus:ring-reddit/55"
    >
      {options.map(([option, label]) => <option key={option} value={option}>{label}</option>)}
    </select>
  );
}
