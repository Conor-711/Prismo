"use client";

// 追踪页（私密）：展示用户追踪(kind="ticker")的标的的当前情况。
// 静态导出友好：服务端把全部标的摘要(gr_ticker / gr_ticker_region)烤进页面，
// 客户端按用户在 Supabase 的 user_collections 过滤出追踪集再渲染（与 ProfileView 同范式）。
import { useEffect, useMemo, useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { useAuth } from "@/components/auth/AuthProvider";
import { useFavorites } from "@/components/favorites/FavoritesProvider";
import { SaveButton } from "@/components/favorites/SaveButton";
import { listCollection } from "@/lib/favorites";
import { Panel } from "@/components/ui";
import { SentScore, Consensus, StanceBar } from "./Bits";
import { TickerLogo } from "./TickerLogo";
import { fmtCompact } from "@/lib/format";
import { regionColor, regionLabel } from "@/lib/regions";
import type { Locale, Dictionary } from "@/lib/i18n";
import type { GrTickerRow, GrRegionCell } from "@/lib/globalQueries";

type T = Dictionary["tracking"];
type SortKey = "added" | "sent" | "posts";

export function TrackingView({
  rows,
  regions,
  lang,
}: {
  rows: GrTickerRow[];
  regions: GrRegionCell[];
  lang: Locale;
}) {
  const { dict } = useLocale();
  const t = dict.tracking;
  const { user, loading } = useAuth();
  const { version } = useFavorites();
  const [tracked, setTracked] = useState<{ symbol: string; added: string }[]>([]);
  const [busy, setBusy] = useState(true);
  const [sort, setSort] = useState<SortKey>("added");

  // 追踪集：user / version 任一变化都重拉（取消追踪后即时消失）
  useEffect(() => {
    let active = true;
    if (!user) {
      setTracked([]);
      setBusy(false);
      return;
    }
    setBusy(true);
    listCollection(user.id, "ticker").then((r) => {
      if (!active) return;
      setTracked(r.map((x) => ({ symbol: x.ref_id.toUpperCase(), added: x.created_at })));
      setBusy(false);
    });
    return () => {
      active = false;
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

  const items = useMemo(() => {
    const list = tracked.map((tk) => ({
      ...tk,
      row: rowMap.get(tk.symbol) ?? null,
      cells: regMap.get(tk.symbol) ?? [],
    }));
    return list.sort((a, b) => {
      if (sort === "added") return a.added < b.added ? 1 : a.added > b.added ? -1 : 0;
      const key = sort === "sent" ? "avg_sentiment" : "total_posts";
      const av = a.row ? a.row[key] : -Infinity;
      const bv = b.row ? b.row[key] : -Infinity;
      return bv - av;
    });
  }, [tracked, rowMap, regMap, sort]);

  if (loading) return <Center>{t.loading}</Center>;
  if (!user) return <SignInPrompt t={t} />;
  if (busy) return <Center>{t.loading}</Center>;
  if (tracked.length === 0) return <EmptyState t={t} />;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <span className="text-xs text-neutral-500 tabular">
          {tracked.length} {t.unit}
        </span>
        <div className="inline-flex rounded-full bg-card ring-1 ring-inset ring-line p-0.5 text-xs">
          {(["sent", "posts", "added"] as const).map((k) => (
            <button
              key={k}
              onClick={() => setSort(k)}
              aria-pressed={sort === k}
              className={`px-3 py-1 rounded-full font-medium transition ${
                sort === k ? "bg-reddit text-white" : "text-neutral-400 hover:text-cream"
              }`}
            >
              {k === "sent" ? t.sortSent : k === "posts" ? t.sortPosts : t.sortAdded}
            </button>
          ))}
        </div>
      </div>

      <div className="space-y-2.5">
        {items.map((it) => (
          <TrackCard key={it.symbol} symbol={it.symbol} row={it.row} cells={it.cells} lang={lang} t={t} />
        ))}
      </div>

      <p className="pt-1 text-center text-[11px] text-neutral-600">{t.updatedHint}</p>
    </div>
  );
}

function TrackCard({
  symbol,
  row,
  cells,
  lang,
  t,
}: {
  symbol: string;
  row: GrTickerRow | null;
  cells: GrRegionCell[];
  lang: Locale;
  t: T;
}) {
  const zh = lang === "zh";
  const name = row ? (zh ? row.name_zh || row.name_en : row.name_en || row.name_zh) : "";

  // 跨区聚合多空占比（按帖数加权）→ 迷你条
  let bull = 0,
    bear = 0,
    neu = 0;
  for (const c of cells) {
    const w = c.post_count || 0;
    bull += (c.bull_pct || 0) * w;
    bear += (c.bear_pct || 0) * w;
    neu += (c.neutral_pct || 0) * w;
  }
  const regs = [...cells].sort((a, b) => (b.post_count || 0) - (a.post_count || 0));

  return (
    <Panel className="p-4">
      <div className="flex items-center gap-3">
        <LocaleLink
          href={`/tickers/${symbol}`}
          className="flex min-w-0 items-center gap-2.5 transition hover:opacity-90"
        >
          <TickerLogo ticker={symbol} size={36} />
          <span className="min-w-0">
            <span className="block font-mono font-bold leading-tight text-cream">{symbol}</span>
            {name && <span className="block max-w-[200px] truncate text-xs text-neutral-500">{name}</span>}
          </span>
        </LocaleLink>

        <span className="flex-1" />

        {row ? (
          <SentScore score={row.avg_sentiment} className="text-lg" />
        ) : (
          <span className="text-xs text-neutral-600">{t.noData}</span>
        )}
        <SaveButton kind="ticker" refId={symbol} variant="follow" size="xs" className="ml-2 shrink-0" />
      </div>

      {row && (
        <>
          <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-neutral-500">
            <span>
              <span className="tabular text-neutral-300">{row.regions_present}</span> {t.regions}
            </span>
            <span>
              <span className="tabular text-neutral-300">{fmtCompact(row.total_posts)}</span> {t.posts}
            </span>
            <span>
              <span className="font-mono tabular text-neutral-300">{(row.spread ?? 0).toFixed(2)}</span> {t.spread}
            </span>
            <span className="ml-auto">
              <Consensus value={row.consensus} lang={lang} />
            </span>
          </div>

          {bull + bear + neu > 0 && <StanceBar bull={bull} bear={bear} neutral={neu} className="mt-2.5" />}

          {regs.length > 0 && (
            <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1.5">
              {regs.map((c) => (
                <span key={c.region} className="inline-flex items-center gap-1.5 text-[12px]">
                  <span
                    className="h-2 w-2 shrink-0 rounded-full"
                    style={{ background: regionColor(c.region) }}
                  />
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

function SignInPrompt({ t }: { t: T }) {
  return (
    <Panel className="mx-auto flex max-w-md flex-col items-center gap-3 px-6 py-14 text-center">
      <span className="grid h-12 w-12 place-items-center rounded-full bg-reddit/10 text-reddit">
        <StarIcon />
      </span>
      <h2 className="font-display font-bold text-cream">{t.signInTitle}</h2>
      <p className="max-w-xs text-sm leading-relaxed text-neutral-500">{t.signInDesc}</p>
      <LocaleLink
        href="/login"
        className="mt-1 inline-flex items-center gap-1 rounded-full bg-reddit px-4 py-2 text-xs font-semibold text-white transition hover:bg-reddit/90"
      >
        {t.signIn} →
      </LocaleLink>
    </Panel>
  );
}

function EmptyState({ t }: { t: T }) {
  return (
    <Panel className="mx-auto flex max-w-md flex-col items-center gap-3 px-6 py-14 text-center">
      <span className="grid h-12 w-12 place-items-center rounded-full bg-reddit/10 text-reddit">
        <StarIcon />
      </span>
      <h2 className="font-display font-bold text-cream">{t.empty}</h2>
      <p className="max-w-xs text-sm leading-relaxed text-neutral-500">{t.emptyDesc}</p>
      <LocaleLink
        href="/tickers"
        className="mt-1 inline-flex items-center gap-1 rounded-full bg-reddit px-4 py-2 text-xs font-semibold text-white transition hover:bg-reddit/90"
      >
        {t.browse} →
      </LocaleLink>
    </Panel>
  );
}
