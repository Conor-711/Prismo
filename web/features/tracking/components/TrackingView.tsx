"use client";

// 追踪页（私密）：展示用户追踪的标的、作者、叙事与社区。
// 静态导出友好：页面把可追踪对象目录烤进 props；客户端只负责读写 Supabase user_collections。
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { useAuth } from "@/components/auth/AuthProvider";
import { useFavorites } from "@/components/favorites/FavoritesProvider";
import { listCollection, type CollectionRow } from "@/lib/favorites";
import { withLang, type Locale } from "@/lib/i18n";
import { SmartVoicePortfolioModule } from "@/features/smart-voice";
import { fmtCompact } from "@/shared/formatting/format";
import type { GrTickerRow, GrRegionCell } from "@/server/queries/globalQueries";
import {
  TRACK_KINDS,
  emptyCollections,
  emptyCounts,
  kindHint,
  kindLabel,
  type ActiveTab,
  type QuickCandidate,
  type SortKey,
  type TrackKind,
  type TrackingCatalog,
} from "../trackingTypes";
import {
  AuthorCard,
  Center,
  CommunityCard,
  EmptyState,
  GenericSection,
  NarrativeCard,
  OverviewButton,
  QuickAdd,
  SignInPrompt,
  TickerSection,
} from "./trackingCards";

export function TrackingView({
  rows,
  regions,
  catalog,
  lang,
}: {
  rows: GrTickerRow[];
  regions: GrRegionCell[];
  catalog: TrackingCatalog;
  lang: Locale;
}) {
  const { dict } = useLocale();
  const t = dict.tracking;
  const zh = lang === "zh";
  const router = useRouter();
  const { user, loading } = useAuth();
  const { version, isSaved } = useFavorites();
  const [collections, setCollections] = useState<Record<TrackKind, CollectionRow[]>>(emptyCollections);
  const [busy, setBusy] = useState(true);
  const [active, setActive] = useState<ActiveTab>("all");
  const [sort, setSort] = useState<SortKey>("added");
  const [query, setQuery] = useState("");

  useEffect(() => {
    let alive = true;
    if (!user) {
      setCollections(emptyCollections());
      setBusy(false);
      return;
    }
    setBusy(true);
    Promise.all(TRACK_KINDS.map((kind) => listCollection(user.id, kind))).then((lists) => {
      if (!alive) return;
      setCollections({
        ticker: lists[0],
        author: lists[1],
        narrative: lists[2],
        subreddit: lists[3],
      });
      setBusy(false);
    });
    return () => {
      alive = false;
    };
  }, [user, version]);

  const rowMap = useMemo(() => {
    const m = new Map<string, GrTickerRow>();
    for (const x of rows) m.set(x.ticker.toUpperCase(), x);
    return m;
  }, [rows]);

  const regMap = useMemo(() => {
    const m = new Map<string, GrRegionCell[]>();
    for (const c of regions) {
      const k = c.ticker.toUpperCase();
      const arr = m.get(k);
      if (arr) arr.push(c);
      else m.set(k, [c]);
    }
    return m;
  }, [regions]);

  const authorMap = useMemo(() => new Map(catalog.authors.map((a) => [a.refId, a])), [catalog.authors]);
  const narrativeMap = useMemo(() => new Map(catalog.narratives.map((n) => [n.refId, n])), [catalog.narratives]);

  const trackedSymbols = useMemo(
    () => collections.ticker.map((r) => r.ref_id.toUpperCase()),
    [collections.ticker],
  );

  const counts = useMemo(() => {
    const out: Record<TrackKind, number> = emptyCounts();
    for (const kind of TRACK_KINDS) out[kind] = collections[kind].length;
    return out;
  }, [collections]);
  const total = TRACK_KINDS.reduce((sum, kind) => sum + counts[kind], 0);

  const quickCandidates = useMemo(() => {
    const tickerItems: QuickCandidate[] = rows.slice(0, 80).map((r) => ({
      kind: "ticker",
      refId: r.ticker.toUpperCase(),
      label: `${r.ticker.toUpperCase()} · ${zh ? r.name_zh || r.name_en : r.name_en || r.name_zh}`,
      sub: `${fmtCompact(r.total_posts)} ${zh ? "讨论" : "posts"} · ${r.regions_present} ${zh ? "社区" : "communities"}`,
      href: `/tickers/${r.ticker.toUpperCase()}`,
      ticker: r.ticker.toUpperCase(),
    }));
    const authorItems: QuickCandidate[] = catalog.authors.slice(0, 80).map((a) => ({
      kind: "author",
      refId: a.refId,
      label: a.name,
      sub: `${a.source} · ${fmtCompact(a.metric)} ${a.source === "YouTube" ? (zh ? "播放" : "views") : (zh ? "互动" : "interactions")}`,
      href: a.href,
      url: a.url,
      avatar: a.avatar,
    }));
    const narrativeItems: QuickCandidate[] = catalog.narratives.map((n) => ({
      kind: "narrative",
      refId: n.refId,
      label: zh ? n.titleZh : n.titleEn,
      sub: `${n.rank ? `#${n.rank} · ` : ""}${(n.share * 100).toFixed(1)}% · ${zh ? n.trendZh : n.trendEn}`,
      href: `/narratives/${n.refId}`,
      color: n.color,
    }));
    const q = query.trim().toLowerCase();
    return [...tickerItems, ...authorItems, ...narrativeItems]
      .filter((c) => !q || `${c.label} ${c.sub} ${c.refId}`.toLowerCase().includes(q))
      .sort((a, b) => {
        const as = isSaved(a.kind, a.refId) ? 1 : 0;
        const bs = isSaved(b.kind, b.refId) ? 1 : 0;
        return as - bs;
      })
      .slice(0, q ? 12 : 10);
  }, [rows, catalog, query, isSaved, lang, zh]);

  if (loading) return <Center>{t.loading}</Center>;
  if (!user) return <SignInPrompt zh={zh} />;

  return (
    <div className="grid min-h-0 gap-4">
      <QuickAdd
        zh={zh}
        query={query}
        setQuery={setQuery}
        candidates={quickCandidates}
        onSeeAll={() => router.push(withLang(lang, active === "author" ? "/investors" : active === "narrative" ? "/narratives" : "/tickers"))}
      />

      <div className="grid grid-cols-2 gap-2 md:grid-cols-3 lg:grid-cols-5">
        {(["all", ...TRACK_KINDS] as ActiveTab[]).map((kind) => (
          <OverviewButton
            key={kind}
            active={active === kind}
            label={kind === "all" ? (zh ? "全部追踪" : "All tracked") : kindLabel(kind, zh)}
            value={kind === "all" ? total : counts[kind]}
            hint={kind === "all" ? (zh ? "总计" : "total") : kindHint(kind, zh)}
            onClick={() => setActive(kind)}
          />
        ))}
      </div>

      {trackedSymbols.length > 0 && (
        <SmartVoicePortfolioModule
          symbols={trackedSymbols}
          zh={zh}
          descZh="按追踪标的等权聚合，快速观察你关注清单里的 SV 投资者强弱。"
          descEn="Equal-weighted by followed tickers, showing the Smart Voice strength around your watchlist."
        />
      )}

      {busy ? (
        <Center>{t.loading}</Center>
      ) : total === 0 ? (
        <EmptyState zh={zh} />
      ) : (
        <div className="grid min-h-0 gap-4">
          {(active === "all" || active === "ticker") && (
            <TickerSection
              rows={collections.ticker}
              rowMap={rowMap}
              regMap={regMap}
              lang={lang}
              sort={sort}
              setSort={setSort}
            />
          )}
          {(active === "all" || active === "author") && (
            <GenericSection
              title={kindLabel("author", zh)}
              count={collections.author.length}
              empty={zh ? "还没有追踪作者。" : "No followed authors yet."}
            >
              {collections.author.map((row) => (
                <AuthorCard key={row.ref_id} row={row} meta={authorMap.get(row.ref_id)} zh={zh} />
              ))}
            </GenericSection>
          )}
          {(active === "all" || active === "narrative") && (
            <GenericSection
              title={kindLabel("narrative", zh)}
              count={collections.narrative.length}
              empty={zh ? "还没有追踪叙事。" : "No followed narratives yet."}
            >
              {collections.narrative.map((row) => (
                <NarrativeCard key={row.ref_id} row={row} meta={narrativeMap.get(row.ref_id)} zh={zh} />
              ))}
            </GenericSection>
          )}
          {(active === "all" || active === "subreddit") && (
            <GenericSection
              title={kindLabel("subreddit", zh)}
              count={collections.subreddit.length}
              empty={zh ? "还没有追踪社区。" : "No followed communities yet."}
            >
              {collections.subreddit.map((row) => (
                <CommunityCard key={row.ref_id} row={row} />
              ))}
            </GenericSection>
          )}
          <p className="text-center text-[11px] text-neutral-600">
            {zh ? "追踪数据实时保存；市场数据随每日构建刷新。" : "Follows save instantly; market data updates with each daily build."}
          </p>
        </div>
      )}
    </div>
  );
}
