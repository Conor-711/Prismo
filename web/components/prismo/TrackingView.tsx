"use client";

// 追踪页（私密）：展示用户追踪的标的、作者、叙事、区域与社区。
// 静态导出友好：页面把可追踪对象目录烤进 props；客户端只负责读写 Supabase user_collections。
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { useAuth } from "@/components/auth/AuthProvider";
import { useFavorites } from "@/components/favorites/FavoritesProvider";
import { SaveButton } from "@/components/favorites/SaveButton";
import { listCollection, type CollectionKind, type CollectionRow } from "@/lib/favorites";
import { withLang, type Locale } from "@/lib/i18n";
import { Panel } from "@/components/ui";
import { SentScore, Consensus, StanceBar } from "./Bits";
import { SmartVoicePortfolioModule } from "./SmartVoiceModules";
import { TickerLogo } from "./TickerLogo";
import { Avatar } from "./kolShared";
import { fmtCompact } from "@/lib/format";
import { regionColor, regionLabel, regionSource } from "@/lib/regions";
import type { GrTickerRow, GrRegionCell } from "@/lib/globalQueries";

type TrackKind = Extract<CollectionKind, "ticker" | "author" | "narrative" | "region" | "subreddit">;
type SortKey = "added" | "sent" | "posts";
type ActiveTab = "all" | TrackKind;

const TRACK_KINDS: TrackKind[] = ["ticker", "author", "narrative", "region", "subreddit"];
const emptyCollections = (): Record<TrackKind, CollectionRow[]> => ({
  ticker: [],
  author: [],
  narrative: [],
  region: [],
  subreddit: [],
});

export interface TrackingAuthorCandidate {
  refId: string;
  source: string;
  name: string;
  avatar?: string;
  url?: string;
  href?: string;
  metric: number;
  posts: number;
  tickers: string[];
}

export interface TrackingNarrativeCandidate {
  refId: string;
  titleZh: string;
  titleEn: string;
  descriptionZh: string;
  descriptionEn: string;
  color: string;
  rank: number | null;
  share: number;
  volume: number;
  trendZh: string;
  trendEn: string;
}

export interface TrackingRegionCandidate {
  refId: string;
  posts: number;
  tickers: number;
  avgSentiment: number;
  bullPct: number;
  bearPct: number;
}

export interface TrackingCatalog {
  authors: TrackingAuthorCandidate[];
  narratives: TrackingNarrativeCandidate[];
  regions: TrackingRegionCandidate[];
}

type QuickCandidate = {
  kind: TrackKind;
  refId: string;
  label: string;
  sub: string;
  href?: string;
  url?: string;
  color?: string;
  avatar?: string;
  ticker?: string;
};

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
        region: lists[3],
        subreddit: lists[4],
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
  const regionMap = useMemo(() => new Map(catalog.regions.map((r) => [r.refId, r])), [catalog.regions]);

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
      sub: `${fmtCompact(r.total_posts)} ${zh ? "讨论" : "posts"} · ${r.regions_present} ${zh ? "区域" : "regions"}`,
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
    const regionItems: QuickCandidate[] = catalog.regions.map((r) => ({
      kind: "region",
      refId: r.refId,
      label: regionLabel(r.refId, lang),
      sub: `${regionSource(r.refId)} · ${fmtCompact(r.posts)} ${zh ? "讨论" : "posts"}`,
      href: `/regions/${r.refId}`,
      color: regionColor(r.refId),
    }));
    const q = query.trim().toLowerCase();
    return [...tickerItems, ...authorItems, ...narrativeItems, ...regionItems]
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
        onSeeAll={() => router.push(withLang(lang, active === "author" ? "/investors" : active === "narrative" ? "/narratives" : active === "region" ? "/regions" : "/tickers"))}
      />

      <div className="grid grid-cols-2 gap-2 md:grid-cols-3 lg:grid-cols-6">
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
          {(active === "all" || active === "region") && (
            <GenericSection
              title={kindLabel("region", zh)}
              count={collections.region.length}
              empty={zh ? "还没有追踪区域。" : "No followed regions yet."}
            >
              {collections.region.map((row) => (
                <RegionCard key={row.ref_id} row={row} meta={regionMap.get(row.ref_id)} lang={lang} />
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

function emptyCounts(): Record<TrackKind, number> {
  return { ticker: 0, author: 0, narrative: 0, region: 0, subreddit: 0 };
}

function kindLabel(kind: TrackKind, zh: boolean) {
  const z: Record<TrackKind, string> = { ticker: "标的", author: "作者", narrative: "叙事", region: "区域", subreddit: "社区" };
  const e: Record<TrackKind, string> = { ticker: "Tickers", author: "Authors", narrative: "Narratives", region: "Regions", subreddit: "Communities" };
  return (zh ? z : e)[kind];
}

function kindHint(kind: TrackKind, zh: boolean) {
  const z: Record<TrackKind, string> = { ticker: "价格与情绪", author: "观点来源", narrative: "市场故事", region: "本土社区", subreddit: "Reddit" };
  const e: Record<TrackKind, string> = { ticker: "prices & sentiment", author: "source voices", narrative: "market stories", region: "native boards", subreddit: "Reddit" };
  return (zh ? z : e)[kind];
}

function QuickAdd({
  zh,
  query,
  setQuery,
  candidates,
  onSeeAll,
}: {
  zh: boolean;
  query: string;
  setQuery: (v: string) => void;
  candidates: QuickCandidate[];
  onSeeAll: () => void;
}) {
  return (
    <Panel className="p-3">
      <div className="flex flex-wrap items-center gap-2">
        <div className="min-w-[180px] flex-1">
          <div className="relative">
            <svg viewBox="0 0 24 24" className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-neutral-600" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="11" cy="11" r="7" />
              <path d="M20 20l-3.5-3.5" />
            </svg>
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={zh ? "搜索并追踪标的、作者、叙事或区域…" : "Search and follow tickers, authors, narratives or regions…"}
              className="h-10 w-full rounded-lg bg-ink/45 pl-9 pr-3 text-[13px] text-cream ring-1 ring-inset ring-line placeholder:text-neutral-600 outline-none transition focus:ring-reddit/70"
            />
          </div>
        </div>
        <button
          type="button"
          onClick={onSeeAll}
          className="h-10 rounded-lg px-3 text-[12px] font-semibold text-neutral-400 ring-1 ring-inset ring-line transition hover:bg-white/[.04] hover:text-cream"
        >
          {zh ? "浏览全部" : "Browse all"}
        </button>
      </div>
      <div className="mt-2 grid gap-2 md:grid-cols-2 xl:grid-cols-5">
        {candidates.map((c) => (
          <QuickCandidateCard key={`${c.kind}:${c.refId}`} c={c} />
        ))}
      </div>
    </Panel>
  );
}

function QuickCandidateCard({ c }: { c: QuickCandidate }) {
  const content = (
    <>
      <Visual c={c} />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[12.5px] font-semibold text-cream">{c.label}</span>
        <span className="mt-0.5 block truncate text-[10.5px] text-neutral-600">{c.sub}</span>
      </span>
    </>
  );
  return (
    <div className="flex min-w-0 items-center gap-2 rounded-lg bg-white/[.025] px-2.5 py-2 ring-1 ring-inset ring-line">
      {c.href ? (
        <LocaleLink href={c.href} className="flex min-w-0 flex-1 items-center gap-2 transition hover:opacity-85">
          {content}
        </LocaleLink>
      ) : c.url ? (
        <a href={c.url} target="_blank" rel="noreferrer noopener" className="flex min-w-0 flex-1 items-center gap-2 transition hover:opacity-85">
          {content}
        </a>
      ) : (
        <div className="flex min-w-0 flex-1 items-center gap-2">{content}</div>
      )}
      <SaveButton kind={c.kind} refId={c.refId} variant="follow" size="xs" className="shrink-0" />
    </div>
  );
}

function Visual({ c }: { c: QuickCandidate }) {
  if (c.ticker) return <TickerLogo ticker={c.ticker} size={24} />;
  if (c.avatar || c.kind === "author") return <Avatar src={c.avatar} color={c.color ?? "#57D7BA"} name={c.label} size={24} />;
  return <span className="h-3 w-3 shrink-0 rounded-sm" style={{ background: c.color ?? "#57D7BA" }} />;
}

function OverviewButton({
  active,
  label,
  value,
  hint,
  onClick,
}: {
  active: boolean;
  label: string;
  value: number;
  hint: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={`rounded-xl px-3 py-3 text-left ring-1 ring-inset transition ${
        active ? "bg-reddit/15 text-cream ring-reddit/60" : "bg-card/75 text-neutral-400 ring-line hover:bg-elevated/70 hover:text-cream"
      }`}
    >
      <div className="font-display text-[24px] font-extrabold leading-none tabular">{value}</div>
      <div className="mt-1.5 truncate text-[12px] font-semibold">{label}</div>
      <div className="mt-0.5 truncate text-[10.5px] text-neutral-600">{hint}</div>
    </button>
  );
}

function TickerSection({
  rows,
  rowMap,
  regMap,
  lang,
  sort,
  setSort,
}: {
  rows: CollectionRow[];
  rowMap: Map<string, GrTickerRow>;
  regMap: Map<string, GrRegionCell[]>;
  lang: Locale;
  sort: SortKey;
  setSort: (s: SortKey) => void;
}) {
  const zh = lang === "zh";
  const items = useMemo(() => {
    const list = rows.map((tk) => ({
      symbol: tk.ref_id.toUpperCase(),
      added: tk.created_at,
      row: rowMap.get(tk.ref_id.toUpperCase()) ?? null,
      cells: regMap.get(tk.ref_id.toUpperCase()) ?? [],
    }));
    return list.sort((a, b) => {
      if (sort === "added") return a.added < b.added ? 1 : a.added > b.added ? -1 : 0;
      const key = sort === "sent" ? "avg_sentiment" : "total_posts";
      const av = a.row ? a.row[key] : -Infinity;
      const bv = b.row ? b.row[key] : -Infinity;
      return bv - av;
    });
  }, [rows, rowMap, regMap, sort]);

  return (
    <GenericSection title={kindLabel("ticker", zh)} count={rows.length} empty={zh ? "还没有追踪标的。" : "No followed tickers yet."}>
      {rows.length > 0 && (
        <div className="mb-2 flex justify-end">
          <div className="inline-flex rounded-full bg-card ring-1 ring-inset ring-line p-0.5 text-xs">
            {(["sent", "posts", "added"] as const).map((k) => (
              <button
                key={k}
                onClick={() => setSort(k)}
                aria-pressed={sort === k}
                className={`rounded-full px-3 py-1 font-medium transition ${
                  sort === k ? "bg-reddit text-white" : "text-neutral-400 hover:text-cream"
                }`}
              >
                {k === "sent" ? (zh ? "情绪" : "Sentiment") : k === "posts" ? (zh ? "热度" : "Activity") : zh ? "最近追踪" : "Recent"}
              </button>
            ))}
          </div>
        </div>
      )}
      {items.map((it) => (
        <TrackTickerCard key={it.symbol} {...it} lang={lang} />
      ))}
    </GenericSection>
  );
}

function GenericSection({
  title,
  count,
  empty,
  children,
}: {
  title: string;
  count: number;
  empty: string;
  children: React.ReactNode;
}) {
  return (
    <section className="min-w-0">
      <div className="mb-2 flex items-center gap-2">
        <h2 className="font-display text-[14px] font-bold text-cream">{title}</h2>
        <span className="rounded bg-white/[.04] px-1.5 py-0.5 font-mono text-[10.5px] text-neutral-500 ring-1 ring-inset ring-white/10">{count}</span>
        <div className="h-px flex-1 bg-line/70" />
      </div>
      {count > 0 ? <div className="grid gap-2.5">{children}</div> : <Panel className="p-5 text-sm text-neutral-600">{empty}</Panel>}
    </section>
  );
}

function TrackTickerCard({
  symbol,
  row,
  cells,
  lang,
}: {
  symbol: string;
  row: GrTickerRow | null;
  cells: GrRegionCell[];
  lang: Locale;
}) {
  const zh = lang === "zh";
  const name = row ? (zh ? row.name_zh || row.name_en : row.name_en || row.name_zh) : "";
  let bull = 0, bear = 0, neu = 0;
  for (const c of cells) {
    const w = c.post_count || 0;
    bull += (c.bull_pct || 0) * w;
    bear += (c.bear_pct || 0) * w;
    neu += (c.neutral_pct || 0) * w;
  }
  const regs = [...cells].sort((a, b) => (b.post_count || 0) - (a.post_count || 0)).slice(0, 5);
  return (
    <Panel className="p-3">
      <div className="flex items-center gap-3">
        <LocaleLink href={`/tickers/${symbol}`} className="flex min-w-0 items-center gap-2.5 transition hover:opacity-90">
          <TickerLogo ticker={symbol} size={34} />
          <span className="min-w-0">
            <span className="block font-mono font-bold leading-tight text-cream">{symbol}</span>
            {name && <span className="block max-w-[260px] truncate text-xs text-neutral-500">{name}</span>}
          </span>
        </LocaleLink>
        <span className="flex-1" />
        {row ? <SentScore score={row.avg_sentiment} className="text-lg" /> : <span className="text-xs text-neutral-600">{zh ? "本期无数据" : "No data"}</span>}
        <SaveButton kind="ticker" refId={symbol} variant="follow" size="xs" className="ml-1 shrink-0" />
      </div>
      {row && (
        <>
          <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-neutral-500">
            <span><span className="tabular text-neutral-300">{row.regions_present}</span> {zh ? "覆盖区" : "regions"}</span>
            <span><span className="tabular text-neutral-300">{fmtCompact(row.total_posts)}</span> {zh ? "帖数" : "posts"}</span>
            <span><span className="font-mono tabular text-neutral-300">{(row.spread ?? 0).toFixed(2)}</span> {zh ? "分歧" : "spread"}</span>
            <span className="ml-auto"><Consensus value={row.consensus} lang={lang} /></span>
          </div>
          {bull + bear + neu > 0 && <StanceBar bull={bull} bear={bear} neutral={neu} className="mt-2" />}
          {regs.length > 0 && (
            <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1">
              {regs.map((c) => (
                <span key={c.region} className="inline-flex items-center gap-1.5 text-[12px]">
                  <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: regionColor(c.region) }} />
                  <span className="text-neutral-400">{regionLabel(c.region, lang)}</span>
                  <SentScore score={c.sentiment_avg} className="text-[11px]" />
                </span>
              ))}
            </div>
          )}
        </>
      )}
    </Panel>
  );
}

function AuthorCard({ row, meta, zh }: { row: CollectionRow; meta?: TrackingAuthorCandidate; zh: boolean }) {
  const label = meta?.name ?? row.ref_id.replace(/^[^:]+:/, "");
  const source = meta?.source ?? row.ref_id.split(":")[0] ?? "Author";
  return (
    <Panel className="flex items-center gap-3 p-3">
      <Avatar src={meta?.avatar} color="#57D7BA" name={label} size={34} />
      <div className="min-w-0 flex-1">
        {meta?.href ? (
          <LocaleLink href={meta.href} className="block truncate text-[13.5px] font-semibold text-cream hover:text-reddit">{label}</LocaleLink>
        ) : meta?.url ? (
          <a href={meta.url} target="_blank" rel="noreferrer noopener" className="block truncate text-[13.5px] font-semibold text-cream hover:text-reddit">{label}</a>
        ) : (
          <div className="truncate text-[13.5px] font-semibold text-cream">{label}</div>
        )}
        <div className="mt-1 flex flex-wrap items-center gap-1.5 text-[11px] text-neutral-600">
          <span>{source}</span>
          {meta && <span>· {fmtCompact(meta.metric)} {source === "YouTube" ? (zh ? "播放" : "views") : (zh ? "互动" : "interactions")}</span>}
          {meta?.tickers.slice(0, 3).map((t) => <span key={t} className="rounded bg-white/[.04] px-1.5 py-px font-mono text-neutral-500">{t}</span>)}
        </div>
      </div>
      <SaveButton kind="author" refId={row.ref_id} variant="follow" size="xs" />
    </Panel>
  );
}

function NarrativeCard({ row, meta, zh }: { row: CollectionRow; meta?: TrackingNarrativeCandidate; zh: boolean }) {
  const title = meta ? (zh ? meta.titleZh : meta.titleEn) : row.ref_id;
  return (
    <Panel className="flex items-center gap-3 p-3">
      <span className="h-8 w-1.5 shrink-0 rounded-full" style={{ background: meta?.color ?? "#57D7BA" }} />
      <div className="min-w-0 flex-1">
        <LocaleLink href={`/narratives/${row.ref_id}`} className="block truncate text-[13.5px] font-semibold text-cream hover:text-reddit">{title}</LocaleLink>
        <div className="mt-1 truncate text-[11px] text-neutral-600">
          {meta ? `${meta.rank ? `#${meta.rank} · ` : ""}${(meta.share * 100).toFixed(1)}% · ${fmtCompact(meta.volume)} ${zh ? "样本" : "samples"} · ${zh ? meta.trendZh : meta.trendEn}` : (zh ? "叙事详情" : "Narrative detail")}
        </div>
      </div>
      <SaveButton kind="narrative" refId={row.ref_id} variant="follow" size="xs" />
    </Panel>
  );
}

function RegionCard({ row, meta, lang }: { row: CollectionRow; meta?: TrackingRegionCandidate; lang: Locale }) {
  const zh = lang === "zh";
  return (
    <Panel className="flex items-center gap-3 p-3">
      <span className="h-8 w-8 shrink-0 rounded-lg ring-1 ring-inset ring-white/10" style={{ background: regionColor(row.ref_id) }} />
      <div className="min-w-0 flex-1">
        <LocaleLink href={`/regions/${row.ref_id}`} className="block truncate text-[13.5px] font-semibold text-cream hover:text-reddit">{regionLabel(row.ref_id, lang)}</LocaleLink>
        <div className="mt-1 truncate text-[11px] text-neutral-600">
          {meta ? `${regionSource(row.ref_id)} · ${fmtCompact(meta.posts)} ${zh ? "讨论" : "posts"} · ${meta.tickers} ${zh ? "标的" : "tickers"}` : regionSource(row.ref_id)}
        </div>
      </div>
      {meta && <SentScore score={meta.avgSentiment} className="text-[13px]" />}
      <SaveButton kind="region" refId={row.ref_id} variant="follow" size="xs" />
    </Panel>
  );
}

function CommunityCard({ row }: { row: CollectionRow }) {
  return (
    <Panel className="flex items-center gap-3 p-3">
      <span className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-white/[.04] text-[11px] text-reddit ring-1 ring-inset ring-line">r/</span>
      <span className="min-w-0 flex-1 truncate text-[13.5px] font-semibold text-cream">r/{row.ref_id}</span>
      <a href={`https://www.reddit.com/r/${row.ref_id}`} target="_blank" rel="noreferrer noopener" className="text-xs text-neutral-600 hover:text-reddit">Reddit ↗</a>
      <SaveButton kind="subreddit" refId={row.ref_id} variant="follow" size="xs" />
    </Panel>
  );
}

function Center({ children }: { children: React.ReactNode }) {
  return <div className="py-24 text-center text-sm text-neutral-500">{children}</div>;
}

function StarIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 3.5l2.6 5.27 5.82.85-4.21 4.1.99 5.78L12 16.77l-5.2 2.73.99-5.78-4.21-4.1 5.82-.85z" />
    </svg>
  );
}

function SignInPrompt({ zh }: { zh: boolean }) {
  return (
    <Panel className="mx-auto flex max-w-md flex-col items-center gap-3 px-6 py-14 text-center">
      <span className="grid h-12 w-12 place-items-center rounded-full bg-reddit/10 text-reddit"><StarIcon /></span>
      <h2 className="font-display font-bold text-cream">{zh ? "登录后查看你的追踪" : "Sign in to see your tracking"}</h2>
      <p className="max-w-xs text-sm leading-relaxed text-neutral-500">
        {zh ? "追踪标的、作者、叙事和区域，随时回来看它们的关键变化。" : "Follow tickers, authors, narratives and regions, then come back to monitor what changed."}
      </p>
      <LocaleLink href="/login" className="mt-1 inline-flex items-center gap-1 rounded-full bg-reddit px-4 py-2 text-xs font-semibold text-white transition hover:bg-reddit/90">
        {zh ? "去登录" : "Sign in"} →
      </LocaleLink>
    </Panel>
  );
}

function EmptyState({ zh }: { zh: boolean }) {
  return (
    <Panel className="mx-auto flex max-w-lg flex-col items-center gap-3 px-6 py-12 text-center">
      <span className="grid h-12 w-12 place-items-center rounded-full bg-reddit/10 text-reddit"><StarIcon /></span>
      <h2 className="font-display font-bold text-cream">{zh ? "还没有追踪任何元素" : "Nothing followed yet"}</h2>
      <p className="max-w-sm text-sm leading-relaxed text-neutral-500">
        {zh ? "从上方搜索框直接添加标的、作者、叙事或区域；之后所有变化都会集中出现在这里。" : "Use the search box above to follow tickers, authors, narratives or regions. Changes will collect here."}
      </p>
    </Panel>
  );
}
